# How to change the wall-image photo source folder

There is no config file for the photo rotation's source folder or interval
— they're hardcoded as `ProgramArguments` inside the LaunchAgent plist
itself (see `README.md`'s "Deployment" section).

## Steps

1. Edit `~/Library/LaunchAgents/com.dennis.wall-photo-producer.plist`,
   changing the `<string>` right after `--source` to the new folder path.
   You can also bump the `--seconds` value in the same edit if you want a
   different rotation interval.

2. Reload the agent so it picks up the change:
   ```
   launchmgr kick wall-photo-producer
   ```
   (or the manual `launchctl unload` / `load` pair on that plist path).

3. After it reloads, `photo_producer.py` starts fresh against the new
   folder. Its shuffle-order/current-index state (`.rotation_state`) lives
   as a hidden file *inside the source folder*, not in this repo — so
   pointing at a folder that's never been used before just starts a new
   rotation; there's nothing to carry over from the old folder.

4. Snapshot the change into `fleet-configs` so it doesn't go stale: run
   `FleetDev/fleetdev-snapshot-fleet-configs.sh`, then `sync-this`/push in
   `fleet-configs` (never commit/push there without asking first — review
   `git status` before committing).
