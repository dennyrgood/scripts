import time
from pathlib import Path
from datetime import datetime, timezone

HEARTBEAT_FILE = Path("D:/OneDrive/_sync_monitor/heartbeat_server.txt")
WRITE_INTERVAL = 300  # 5 minutes

while True:
    HEARTBEAT_FILE.parent.mkdir(parents=True, exist_ok=True)
    HEARTBEAT_FILE.write_text(datetime.now(timezone.utc).isoformat())
    time.sleep(WRITE_INTERVAL)
