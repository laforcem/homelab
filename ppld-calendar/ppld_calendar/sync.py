"""Make the CalDAV calendar's ppld-* objects match the desired events."""
import logging
from dataclasses import dataclass, field

from .caldav import CalDavError
from .events import Event, render_ics

log = logging.getLogger("ppld-calendar")


@dataclass
class SyncResult:
    put: int = 0
    deleted: int = 0
    errors: list[str] = field(default_factory=list)


def run_sync(events: list[Event], client, dry_run: bool = False) -> SyncResult:
    desired = {e.filename: e for e in events}
    existing = client.list_managed()  # raises before any write if the calendar is unreadable
    stale = sorted(existing - desired.keys())
    result = SyncResult()

    for name, event in sorted(desired.items()):
        if dry_run:
            log.info("dry-run: would PUT %s (%s on %s)", name, event.summary, event.day)
            result.put += 1
            continue
        try:
            client.put(name, render_ics(event))
            result.put += 1
        except CalDavError as e:
            result.errors.append(str(e))

    for name in stale:
        if dry_run:
            log.info("dry-run: would DELETE %s", name)
            result.deleted += 1
            continue
        try:
            client.delete(name)
            result.deleted += 1
        except CalDavError as e:
            result.errors.append(str(e))

    return result
