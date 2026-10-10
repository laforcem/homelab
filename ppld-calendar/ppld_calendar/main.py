"""One sync run: PPLD -> events -> CalDAV, with a healthchecks.io ping."""
import logging
import os
import sys
import urllib.request
from typing import Mapping

from . import ppld
from .caldav import CalDavClient
from .events import checkout_to_event
from .sync import run_sync

log = logging.getLogger("ppld-calendar")

REQUIRED = (
    "PPLD_CARD_NUMBER",
    "PPLD_PIN",
    "CALDAV_USERNAME",
    "CALDAV_APP_PASSWORD",
    "CALDAV_CALENDAR_URL",
    "HEALTHCHECK_URL",
)


def ping(url: str, suffix: str = "") -> None:
    try:
        urllib.request.urlopen(url.rstrip("/") + suffix, timeout=10).close()
    except Exception as e:  # a failed ping must never change the run's outcome
        log.warning("healthcheck ping failed: %s", type(e).__name__)


def _sync_once(env: Mapping[str, str]) -> None:
    token = ppld.login(env["PPLD_CARD_NUMBER"], env["PPLD_PIN"])
    checkouts = ppld.fetch_checkouts(token)
    holds = ppld.fetch_holds(token)
    events = [checkout_to_event(item) for item in checkouts]  # parse everything before any write
    log.info("fetched %d checkouts, %d holds", len(checkouts), len(holds))
    if holds:
        first = holds[0]
        fields = sorted(first) if isinstance(first, dict) else type(first).__name__
        log.info("holds are not synced yet; first hold fields: %s", fields)

    client = CalDavClient(
        env["CALDAV_CALENDAR_URL"], env["CALDAV_USERNAME"], env["CALDAV_APP_PASSWORD"]
    )
    result = run_sync(events, client, dry_run=env.get("DRY_RUN") == "1")
    log.info("put %d, deleted %d, errors %d", result.put, result.deleted, len(result.errors))
    if result.errors:
        raise RuntimeError("CalDAV operations failed: " + "; ".join(result.errors))


def main(environ: Mapping[str, str] | None = None) -> int:
    env = os.environ if environ is None else environ
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    hc = env.get("HEALTHCHECK_URL", "")
    try:
        missing = [k for k in REQUIRED if not env.get(k)]
        if missing:
            raise RuntimeError("missing env: " + ", ".join(missing))
        _sync_once(env)
    except Exception as e:
        log.error("sync failed: %s", e)
        if hc:
            ping(hc, "/fail")
        return 1
    ping(hc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
