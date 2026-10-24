#!/usr/bin/python3
"""notes_to_self_to_email.py -- email every iMessage you text yourself to Yahoo.
Created: 2026-10-24.

WHY THIS EXISTS
  Thoughts captured on the go get texted to yourself in Messages, where they
  sink. This lands each one in dennyrgood@yahoo.com instead, with no change of
  habit: keep texting yourself.

HOW
  FleetDev's Messages.app is signed into the same Apple ID as the phone, so its
  ~/Library/Messages/chat.db receives a copy of every note-to-self within
  seconds. Every minute (LaunchAgent com.dennis.notes-to-self) this:
    1. reads chat.db for messages newer than the last one handled, ONLY in the
       notes-to-self conversation (chat identifier is one of SELF_HANDLES) and
       sent by you -- other conversations are never selected. A note can be
       stored on this Mac as a *received* copy (is_from_me=0, from your own
       other address) instead of a sent one, so both are accepted; a received
       copy is held ECHO_WAIT seconds and skipped if a sent twin shows up;
    2. decodes the text (newer macOS leaves message.text NULL and stores it in
       attributedBody, an NSAttributedString typedstream);
    3. mails each one via msmtp (account "icloud" in ~/.msmtprc);
    4. attaches photos and PDFs sent with the note (HEIC is converted to JPEG with
       sips); anything over MAX_ATTACH_BYTES is left off and named in the body;
    5. records the highest ROWID handled, so nothing is sent twice and a sleeping
       Mac just delays delivery -- no note is lost.

  s3g_reachability_probe.sh on wbu sends its alerts into this same conversation
  (via this Mac's Messages), so those are recognised by prefix and skipped.

  First run with no state starts from the newest message: no backlog is mailed.

PERMISSION
  Reading chat.db needs Full Disk Access for the binary launchd runs
  (/usr/bin/python3, the same grant com.dennis.heartbeat-writer uses). See
  launchagents/README.md. Without it every run logs "unable to open database".
"""

import binascii
import mimetypes
import datetime
import os
import sqlite3
import subprocess
import sys
import tempfile
from email.message import EmailMessage

HOME = os.path.expanduser("~")
CHAT_DB = f"{HOME}/Library/Messages/chat.db"
MSMTP = "/opt/homebrew/bin/msmtp"
SELF_HANDLES = ["dennyrgood@yahoo.com", "dennis.mathes@icloud.com", "+17173776925"]
TO = "dennyrgood@yahoo.com"
STATE = f"{HOME}/.local/state/notes-to-self.state"
# Our own alerts, not notes. Matched on the start of the text.
SKIP_PREFIXES = ("s3g is back online", "[TEST] s3g is back online")

MAX_ATTACH_BYTES = 20 * 1024 * 1024

ECHO_WAIT = 75  # seconds a received-only copy waits for its sent twin

APPLE_EPOCH = 978307200  # 2001-01-01, Messages' date origin (date is in ns)


def log(msg):
    # launchd sends stdout to ~/Library/Logs/notes_to_self.log
    print(f"[{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%dT%H:%M:%SZ}] {msg}", flush=True)


def decode_body(blob):
    """Pull the plain string out of an NSAttributedString typedstream."""
    if not blob:
        return None
    b = bytes(blob)
    i = b.find(b"NSString")
    if i < 0:
        return None
    j = b.find(b"+", i)
    if j < 0 or j + 1 >= len(b):
        return None
    n, k = b[j + 1], j + 2
    if n == 0x81:            # 2-byte little-endian length follows
        n, k = int.from_bytes(b[k:k + 2], "little"), k + 2
    elif n == 0x82:          # 4-byte
        n, k = int.from_bytes(b[k:k + 4], "little"), k + 4
    return b[k:k + n].decode("utf-8", "replace")


def get_attachments(db, rowid, tmp):
    """Photos/PDFs on one message -> ([(filename, mime, bytes)], [skipped notes]).
    Link-preview payloads have no mime type, so they never match."""
    rows = db.execute("""
        select a.filename, a.mime_type, a.transfer_name
        from attachment a join message_attachment_join j on j.attachment_id = a.ROWID
        where j.message_id = ? and (a.mime_type like 'image/%' or a.mime_type = 'application/pdf')
        order by a.ROWID""", (rowid,)).fetchall()
    out, skipped = [], []
    for path, mime, name in rows:
        name = name or os.path.basename(path or "") or "attachment"
        path = os.path.expanduser(path or "")
        if not os.path.isfile(path):
            skipped.append(f"{name} (file not found on this Mac)")
            continue
        if mime in ("image/heic", "image/heif"):
            jpg = os.path.join(tmp, os.path.splitext(os.path.basename(name))[0] + ".jpg")
            r = subprocess.run(["/usr/bin/sips", "-s", "format", "jpeg", path, "--out", jpg],
                               capture_output=True, timeout=60)
            if r.returncode != 0 or not os.path.isfile(jpg):
                skipped.append(f"{name} (HEIC conversion failed)")
                continue
            path, mime, name = jpg, "image/jpeg", os.path.basename(jpg)
        size = os.path.getsize(path)
        if size > MAX_ATTACH_BYTES:
            skipped.append(f"{name} ({size / 1048576:.0f} MB, over the {MAX_ATTACH_BYTES >> 20} MB limit)")
            continue
        with open(path, "rb") as f:
            out.append((name, mime, f.read()))
    return out, skipped


def sum_bytes(db, rowid):
    return db.execute("""select ifnull(sum(a.total_bytes),0) from message_attachment_join j
                          join attachment a on a.ROWID = j.attachment_id where j.message_id = ?""",
                      (rowid,)).fetchone()[0]


def is_echo(db, rowid, date_ns, body, nbytes):
    """True if a sent (is_from_me=1) twin of this received copy exists: same text
    and attachment size, within two minutes, in the self conversation."""
    marks = ",".join("?" * len(SELF_HANDLES))
    for text, blob, tb in db.execute(f"""
            select ifnull(m.text,''), m.attributedBody,
                   (select ifnull(sum(a.total_bytes),0) from message_attachment_join j
                      join attachment a on a.ROWID = j.attachment_id where j.message_id = m.ROWID)
            from message m
            join chat_message_join cj on cj.message_id = m.ROWID
            join chat c on c.ROWID = cj.chat_id
            where m.is_from_me = 1 and m.ROWID <> ? and abs(m.date - ?) < 120000000000
              and c.chat_identifier in ({marks})""", [rowid, date_ns] + SELF_HANDLES):
        twin = (text or decode_body(blob) or "").replace("\ufffc", "").strip()
        if twin == body and tb == nbytes:
            return True
    return False


def send(text, when_utc, attachments=(), skipped=()):
    first = " ".join(text.split())
    if not first:
        first = "[PDF]" if attachments and all(a[1] == "application/pdf" for a in attachments) else "[photo]"
    subject = "Note: " + (first[:70] + "..." if len(first) > 70 else first)
    m = EmailMessage()
    m["To"] = TO
    m["Subject"] = subject
    local = when_utc.astimezone()
    if skipped:
        text = (text + "\n\n" if text else "") + "[not attached: " + "; ".join(skipped) + "]"
    m.set_content(f"{text}\n\n--\ntexted to yourself {local:%a %d %b %Y %H:%M %Z}\n"
                  f"(notes_to_self_to_email.py on FleetDev, from Messages)\n")
    for name, mime, data in attachments:
        mt, st = (mime or mimetypes.guess_type(name)[0] or "application/octet-stream").split("/", 1)
        m.add_attachment(data, maintype=mt, subtype=st, filename=name)
    r = subprocess.run([MSMTP, "--account=icloud", TO], input=m.as_bytes(),
                       capture_output=True, timeout=60)
    if r.returncode != 0:
        raise RuntimeError(f"msmtp rc={r.returncode}: {r.stderr.decode(errors='replace').strip()[:200]}")


def write_state(rowid):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"{rowid}\n")
    os.replace(tmp, STATE)


def main():
    last = None
    if os.path.exists(STATE):
        with open(STATE) as f:
            last = int(f.read().strip() or 0)

    db = sqlite3.connect(f"file:{CHAT_DB}?mode=ro", uri=True, timeout=10)
    try:
        if last is None:
            newest = db.execute("select ifnull(max(ROWID),0) from message").fetchone()[0]
            write_state(newest)
            log(f"initialised at ROWID {newest}; only notes after this are mailed")
            return

        marks = ",".join("?" * len(SELF_HANDLES))
        rows = db.execute(f"""
            select m.ROWID, m.date, ifnull(m.text,''), m.attributedBody, m.is_from_me
            from message m
            join chat_message_join cmj on cmj.message_id = m.ROWID
            join chat c on c.ROWID = cmj.chat_id
            where m.ROWID > ?
              and c.chat_identifier in ({marks})
            group by m.ROWID
            order by m.ROWID
        """, [last] + SELF_HANDLES).fetchall()
    finally:
        db.close()

    adb = sqlite3.connect(f"file:{CHAT_DB}?mode=ro", uri=True, timeout=10)
    now_ns = (datetime.datetime.now(datetime.timezone.utc).timestamp() - APPLE_EPOCH) * 1e9
    for rowid, date_ns, text, blob, from_me in rows:
        # Attachment-only messages carry just U+FFFC (object replacement char) as text.
        body = (text or decode_body(blob) or "").replace("\ufffc", "").strip()
        when = datetime.datetime.fromtimestamp(date_ns / 1e9 + APPLE_EPOCH, datetime.timezone.utc)
        if not from_me and now_ns - date_ns < ECHO_WAIT * 1e9:
            return   # received copy: wait for its sent twin; state stays put, retried next minute
        if body.startswith(SKIP_PREFIXES):
            log(f"ROWID {rowid}: s3g alert -- skipped")
        elif not from_me and is_echo(adb, rowid, date_ns, body, sum_bytes(adb, rowid)):
            log(f"ROWID {rowid}: received copy of a note already handled as sent -- skipped")
        else:
            with tempfile.TemporaryDirectory() as tmp:
                atts, skipped = get_attachments(adb, rowid, tmp)
                if not body and not atts and not skipped:
                    log(f"ROWID {rowid}: no text or photo/PDF (other attachment type?) -- skipped")
                else:
                    send(body, when, atts, skipped)   # raises -> state not advanced -> retried next minute
                    log(f"ROWID {rowid}: mailed ({len(body)} chars, {len(atts)} attached, {len(skipped)} skipped)")
        write_state(rowid)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # launchd: try again next minute, but leave a trace
        log(f"ERROR: {e}")
        sys.exit(1)
