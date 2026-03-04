"""
checker.py — Fleet Checker Entry Point
Launched by Windows Task Scheduler on Amsterdam.
Configures logging, then hands off to engine.run_forever().
Runs silently with no ports or web server.
"""

import logging
import sys
from pathlib import Path

# Bootstrap path so relative imports work when launched by Task Scheduler
sys.path.insert(0, str(Path(__file__).parent))

from config import STATUS_DIR, CHECKER_HOST
import engine


def _configure_logging() -> None:
    """
    Log to both console (for Task Scheduler capture) and a rotating file
    in the same STATUS_DIR as JSON outputs. INFO level by default.
    """
    STATUS_DIR.mkdir(parents=True, exist_ok=True)
    log_file = STATUS_DIR / f"checker_{CHECKER_HOST}_app.log"

    fmt = "%(asctime)s [%(levelname)s] %(name)s — %(message)s"
    datefmt = "%Y-%m-%dT%H:%M:%SZ"

    handlers = [
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(log_file, encoding="utf-8"),
    ]

    logging.basicConfig(
        level=logging.INFO,
        format=fmt,
        datefmt=datefmt,
        handlers=handlers,
    )

    # Suppress noisy urllib3 / urllib debug output
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("urllib").setLevel(logging.WARNING)


if __name__ == "__main__":
    _configure_logging()
    engine.run_forever()
