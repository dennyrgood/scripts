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
       sent by you -- other conversations are never selected;
    2. decodes the text (newer macOS leaves message.text NULL and stores it in
       attributedBody, an NSAttributedString typedstream);
    3. mails each one via msmtp (account "icloud" in ~/.msmtprc);
    4. records the highest ROWID handled, so nothing is sent twice and a sleeping
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
import datetime
import os
import sqlite3
import subprocess
import sys
from email.message import EmailMessage

HOME = os.path.expanduser("~")
CHAT_DB = f"{HOME}/Library/Messages/chat.db"
MSMTP = "/opt/homebrew/bin/msmtp"
SELF_HANDLES = ["dennyrgood@yahoo.com", "dennis.mathes@icloud.com", "+17173776925"]
TO = "dennyrgood@yahoo.com"
STATE = f"{HOME}/.local/state/notes-to-self.state"
# Our own alerts, not notes. Matched on the start of the text.
SKIP_PREFIXES = ("s3g is back online", "[TEST] s3g is back online")

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


def send(text, when_utc):
    first = " ".join(text.split())
    subject = "Note: " + (first[:70] + "..." if len(first) > 70 else first)
    m = EmailMessage()
    m["To"] = TO
    m["Subject"] = subject
    local = when_utc.astimezone()
    m.set_content(f"{text}\n\n--\ntexted to yourself {local:%a %d %b %Y %H:%M %Z}\n"
                  f"(notes_to_self_to_email.py on FleetDev, from Messages)\n")
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
            select m.ROWID, m.date, ifnull(m.text,''), m.attributedBody
            from message m
            join chat_message_join cmj on cmj.message_id = m.ROWID
            join chat c on c.ROWID = cmj.chat_id
            where m.ROWID > ? and m.is_from_me = 1
              and c.chat_identifier in ({marks})
            group by m.ROWID
            order by m.ROWID
        """, [last] + SELF_HANDLES).fetchall()
    finally:
        db.close()

    for rowid, date_ns, text, blob in rows:
        body = text or decode_body(blob)
        when = datetime.datetime.fromtimestamp(date_ns / 1e9 + APPLE_EPOCH, datetime.timezone.utc)
        if not body or not body.strip():
            log(f"ROWID {rowid}: no text (photo/attachment?) -- skipped")
        elif body.startswith(SKIP_PREFIXES):
            log(f"ROWID {rowid}: s3g alert -- skipped")
        else:
            send(body, when)   # raises -> state not advanced -> retried next minute
            log(f"ROWID {rowid}: mailed ({len(body)} chars)")
        write_state(rowid)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # launchd: try again next minute, but leave a trace
        log(f"ERROR: {e}")
        sys.exit(1)
