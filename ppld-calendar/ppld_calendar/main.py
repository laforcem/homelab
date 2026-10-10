"""One sync run: PPLD -> events -> CalDAV, with a healthchecks.io ping."""
import logging
import os
import sys
import urllib.request
from typing import Mapping

from . import ppld
from .caldav import CalDavClient, CalDavError
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


class SyncFailed(RuntimeError):
    """Raised by main itself; its message is safe to log."""


def _log_holds_shape(holds) -> None:
    """Holds are not synced yet; log field names only, never values."""
    if holds is None:
        return
    if isinstance(holds, list):
        if holds and isinstance(holds[0], dict):
            log.info("holds: %d; first hold fields: %s", len(holds), sorted(holds[0]))
        else:
            log.info("holds: %d", len(holds))
    elif isinstance(holds, dict):
        log.info("holds response keys: %s", sorted(holds))
    else:
        log.info("holds response type: %s", type(holds).__name__)


def _sync_once(env: Mapping[str, str]) -> None:
    token = ppld.login(env["PPLD_CARD_NUMBER"], env["PPLD_PIN"])
    checkouts = ppld.fetch_checkouts(token)
    try:
        holds = ppld.fetch_holds(token)
    except ppld.PpldError as e:
        log.warning("holds fetch failed (ignored): %s", e)
        holds = None
    events = [checkout_to_event(item) for item in checkouts]  # parse everything before any write
    log.info("fetched %d checkouts", len(checkouts))
    _log_holds_shape(holds)

    client = CalDavClient(
        env["CALDAV_CALENDAR_URL"], env["CALDAV_USERNAME"], env["CALDAV_APP_PASSWORD"]
    )
    result = run_sync(events, client, dry_run=env.get("DRY_RUN") == "1")
    log.info("put %d, deleted %d, errors %d", result.put, result.deleted, len(result.errors))
    if result.errors:
        raise SyncFailed("CalDAV operations failed: " + "; ".join(result.errors))


def main(environ: Mapping[str, str] | None = None) -> int:
    env = os.environ if environ is None else environ
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    hc = env.get("HEALTHCHECK_URL", "")
    try:
        missing = [k for k in REQUIRED if not env.get(k)]
        if missing:
            raise SyncFailed("missing env: " + ", ".join(missing))
        _sync_once(env)
    except Exception as e:
        if isinstance(e, (ppld.PpldError, CalDavError, SyncFailed)):
            log.error("sync failed: %s", e)
        else:  # arbitrary exceptions may embed the calendar URL or account email
            log.error("sync failed: %s", type(e).__name__)
        if hc:
            ping(hc, "/fail")
        return 1
    ping(hc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
