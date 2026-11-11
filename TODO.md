# TODO

## Add `timeout 60` to `/etc/msmtprc` on wbu and cwhu (added 2026-11-11)

On 2026-11-11 the 9046unix nightly summary hung for ~5 h in `msmtp`: a Wi-Fi drop
mid-send left the SMTP connection open, and msmtp has no default timeout, so it
waited forever and the email never went out. Fixed on 9046unix by adding
`timeout 60` under `defaults` in `/etc/msmtprc` (plus a 3x retry in
`9046Unix/9046unix-nightly-summary.sh`).

wbu (workbenchunix) and cwhu (chatworkhorseunix) use the same msmtprc layout
(iCloud SMTP), so they likely have the same gap. On each box:

- `sudo grep -n timeout /etc/msmtprc` — if nothing, add `    timeout 60` on the
  line after `defaults`.
- Optionally give their nightly-summary / alert scripts the same retry loop.
