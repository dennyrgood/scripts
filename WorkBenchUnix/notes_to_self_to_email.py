#!/usr/bin/env python3
"""notes_to_self_to_email.py -- email every iMessage you text yourself to Yahoo.
Created: 2026-10-24.

WHY THIS EXISTS
  Thoughts captured on the go get texted to yourself in Messages, where they
  sink. This lands each one in dennyrgood@yahoo.com instead, with no change of
  habit: keep texting yourself.

HOW
  FleetDev's Messages.app is signed into the same Apple ID as the phone, so its
  ~/Library/Messages/chat.db receives a copy of every note-to-self within
  seconds. Every minute (root cron on wbu) this:
    1. asks FleetDev over ssh (as dhm -- root has no key there) for messages
       newer than the last one handled, ONLY in the notes-to-self conversation
       (chat identifier is one of SELF_HANDLES) and sent by you;
    2. decodes the text (newer macOS leaves message.text NULL and stores it in
       attributedBody, an NSAttributedString typedstream);
    3. mails each one via msmtp (root-only config, hence root cron);
    4. records the highest ROWID handled, so nothing is sent twice and a
       FleetDev outage just delays delivery -- no note is lost.
  Other conversations are never read.

  s3g_reachability_probe.sh sends its alerts into this same conversation, so
  those are recognised by prefix and skipped.

  First run with no state starts from the newest message: no backlog is mailed.
"""

import binascii
import datetime
import os
import subprocess
import sys
from email.message import EmailMessage

FLEETDEV = "dennishmathes@fleetdev"
SELF_HANDLES = ["dennyrgood@yahoo.com", "dennis.mathes@icloud.com", "+17173776925"]
TO = "dennyrgood@yahoo.com"
STATE = "/var/lib/notes-to-self.state"
LOG = "/var/log/notes-to-self.log"
# Our own alerts, not notes. Matched on the start of the text.
SKIP_PREFIXES = ("s3g is back online", "[TEST] s3g is back online")

APPLE_EPOCH = 978307200  # 2001-01-01, Messages' date origin (date is in ns)


def log(msg):
    line = f"[{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%dT%H:%M:%SZ}] {msg}"
    with open(LOG, "a") as f:
        f.write(line + "\n")


def remote_sql(sql):
    # sqlite3 reads the query from stdin, so no shell quoting of handles or SQL.
    r = subprocess.run(
        ["sudo", "-u", "dhm", "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
         FLEETDEV, "sqlite3 -separator '|' ~/Library/Messages/chat.db"],
        input=sql, capture_output=True, text=True, timeout=45)
    if r.returncode != 0:
        raise RuntimeError(f"ssh/sqlite3 rc={r.returncode}: {r.stderr.strip()[:200]}")
    return r.stdout


def decode_body(hexblob):
    """Pull the plain string out of an NSAttributedString typedstream."""
    if not hexblob:
        return None
    b = binascii.unhexlify(hexblob)
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
                  f"(notes_to_self_to_email.py on wbu, via FleetDev Messages)\n")
    r = subprocess.run(["msmtp", "--account=icloud", TO], input=m.as_bytes(), capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"msmtp rc={r.returncode}: {r.stderr.decode(errors='replace').strip()[:200]}")


def main():
    if os.geteuid() != 0:
        sys.exit("FAILED: run as root (msmtp config is root-only)")

    last = None
    if os.path.exists(STATE):
        with open(STATE) as f:
            last = int(f.read().strip() or 0)

    if last is None:
        newest = remote_sql("select ifnull(max(ROWID),0) from message;").strip()
        with open(STATE, "w") as f:
            f.write(newest + "\n")
        log(f"initialised at ROWID {newest}; only notes after this are mailed")
        return

    handles = ",".join("'" + h.replace("'", "''") + "'" for h in SELF_HANDLES)
    rows = remote_sql(f"""
        select m.ROWID, m.date, ifnull(m.text,''), hex(m.attributedBody)
        from message m
        join chat_message_join cmj on cmj.message_id = m.ROWID
        join chat c on c.ROWID = cmj.chat_id
        where m.ROWID > {last} and m.is_from_me = 1
          and c.chat_identifier in ({handles})
        group by m.ROWID
        order by m.ROWID;
    """)

    for line in rows.splitlines():
        rowid, date_ns, text, hexblob = line.split("|", 3)
        rowid = int(rowid)
        body = text or decode_body(hexblob)
        when = datetime.datetime.fromtimestamp(int(date_ns) / 1e9 + APPLE_EPOCH, datetime.timezone.utc)
        if not body or not body.strip():
            log(f"ROWID {rowid}: no text (photo/attachment?) -- skipped")
        elif body.startswith(SKIP_PREFIXES):
            log(f"ROWID {rowid}: s3g alert -- skipped")
        else:
            send(body, when)   # raises -> state not advanced -> retried next minute
            log(f"ROWID {rowid}: mailed ({len(body)} chars)")
        with open(STATE, "w") as f:
            f.write(f"{rowid}\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # cron: keep going next minute, but leave a trace
        log(f"ERROR: {e}")
        sys.exit(1)
