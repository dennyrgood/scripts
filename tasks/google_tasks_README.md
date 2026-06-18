<!-- google_tasks_README.md — Created: 2026-06-17 20:15 -->

# Google Tasks Export

A small Python tool that pulls all tasks from your default Google Tasks list
and writes them, with full details, to `google_tasks.txt`.

Location: `~/Desktop/Vault/tasks/`
Script: `export_tasks.py`
Scope: read-only (`tasks.readonly`) — it cannot modify or delete anything.

---

## Setup (one time)

This was done once and shouldn't need repeating, but recorded here for reference
or for rebuilding on another machine.

1. **Google Cloud project** — created "My First Project" in the
   [Google Cloud Console](https://console.cloud.google.com/).

2. **Enable the Tasks API** — at
   [Tasks API library](https://console.cloud.google.com/apis/library/tasks.googleapis.com),
   project selected, clicked **Enable**. (Free, no billing required.)

3. **OAuth consent screen** — configured as **External**, in **Testing** mode.

4. **Test user** — added `Dr.Dennis.H.Mathes@gmail.com` under
   [Audience → Test users](https://console.cloud.google.com/auth/audience).
   Required, or the sign-in returns `Error 403: access_denied`.

5. **OAuth client** — created an **OAuth client ID** of type **Desktop app**,
   downloaded the JSON, renamed it to `credentials.json`, and placed it in
   `~/Desktop/Vault/`.

6. **Python environment** — Homebrew Python blocks system-wide pip installs, so
   a virtual environment was used:

   ```
   cd ~/Desktop/Vault/tasks
   python3 -m venv venv
   source venv/bin/activate
   pip install google-api-python-client google-auth-oauthlib
   ```

7. **First run** — `python3 export_tasks.py` opened a browser for consent.
   On the "unverified app" warning, chose **Advanced → Go to TasksAccess (unsafe)**
   (safe — it's your own unpublished app). This saved `token.json` for reuse.

Files now in the folder:
- `export_tasks.py` — the script
- `run.sh` — convenience wrapper (cd + activate + run); start it with `#!/bin/bash`
- `credentials.json` — OAuth client (keep private; do not share)
- `token.json` — saved login (keep private; do not share)
- `venv/` — the Python environment
- `google_tasks.txt` — the output

---

## Re-run (every time after)

```
cd ~/Desktop/Vault/tasks
source venv/bin/activate
python3 export_tasks.py
```

Or use the wrapper (must be run with bash, not `sh` — `source` misbehaves under `sh`):

```
cd ~/Desktop/Vault/tasks
./run.sh
```

This overwrites `google_tasks.txt` with the current tasks. No browser prompt —
the saved `token.json` is reused. If the token ever expires or is deleted, the
browser consent step runs again automatically.

View the result:

```
cat google_tasks.txt
```

---

## Suggested uses

- **Snapshot / backup** — keep a plain-text record of your task list that
  doesn't depend on the Google Tasks UI, easy to grep or diff over time.
- **Vault integration** — since the output lives in your Vault, it's searchable
  alongside your other notes (e.g. in Obsidian or whatever indexes that folder).
- **Scheduled export** — wrap the re-run commands in a shell script and trigger
  it from `cron` or a macOS `launchd` agent (e.g. daily) for an automatic
  rolling snapshot.
- **Feed into other tooling** — the text file is trivial to parse; you could
  pipe it into a summary, a weekly review, or your fleet dashboards.
- **Extend the script** — flip the scope from `tasks.readonly` to `tasks` and
  it could create or complete tasks too, if you ever want write access. (Would
  need a re-consent for the broader scope.)

---

## Note: moving the folder

The venv does not survive being moved — its internal paths are absolute. If you
relocate the `tasks/` folder, delete and recreate the venv in the new spot:

```
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install google-api-python-client google-auth-oauthlib
```

Everything else (`export_tasks.py`, `credentials.json`, `token.json`) moves fine.
