"""Turn PPLD checkout records into all-day calendar events."""
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

LOCAL_TZ = ZoneInfo("America/Denver")
_ID_RE = re.compile(r"^[A-Za-z0-9-]+$")


@dataclass(frozen=True)
class Event:
    uid: str
    filename: str
    summary: str
    description: str
    day: date
    stamp: datetime  # UTC; derived from the record so repeated PUTs are identical


def parse_utc(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def local_date(value: str) -> date:
    return parse_utc(value).astimezone(LOCAL_TZ).date()


def checkout_to_event(item: dict) -> Event:
    item_id = str(item["id"])
    if not _ID_RE.match(item_id):
        raise ValueError(f"unexpected checkout id: {item_id!r}")
    resource = item["resource"]
    limit = item.get("renewalLimit", 0)
    used = item.get("renewalCount", 0)
    if item.get("canItemBeRenewed", False):
        renewal = f"Renewable ({limit - used} of {limit} renewals left)"
    else:
        renewal = "Not renewable"
    kind = resource.get("materialType", "Item")
    vendor = item.get("vendor", "unknown")
    return Event(
        uid=f"ppld-checkout-{item_id}@homelab",
        filename=f"ppld-checkout-{item_id}.ics",
        summary=f"Due: {resource['title']}",
        description=f"{renewal}\n{kind} via {vendor}",
        day=local_date(item["dueDate"]),
        stamp=parse_utc(item["checkOutDate"]),
    )


def _escape(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )


def _fold(line: str) -> list[str]:
    """RFC 5545 line folding: max 75 octets per line, continuations start with a space."""
    if len(line.encode("utf-8")) <= 75:
        return [line]
    out, cur, cur_len = [], "", 0
    for ch in line:
        n = len(ch.encode("utf-8"))
        if cur_len + n > 75:
            out.append(cur)
            cur, cur_len = " " + ch, 1 + n
        else:
            cur += ch
            cur_len += n
    out.append(cur)
    return out


def render_ics(ev: Event) -> str:
    end = ev.day + timedelta(days=1)
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//homelab//ppld-calendar//EN",
        "BEGIN:VEVENT",
        f"UID:{ev.uid}",
        f"DTSTAMP:{ev.stamp.strftime('%Y%m%dT%H%M%SZ')}",
        f"DTSTART;VALUE=DATE:{ev.day.strftime('%Y%m%d')}",
        f"DTEND;VALUE=DATE:{end.strftime('%Y%m%d')}",
        f"SUMMARY:{_escape(ev.summary)}",
        f"DESCRIPTION:{_escape(ev.description)}",
        "BEGIN:VALARM",
        "ACTION:DISPLAY",
        f"DESCRIPTION:{_escape(ev.summary)}",
        "TRIGGER:-PT15H",
        "END:VALARM",
        "END:VEVENT",
        "END:VCALENDAR",
    ]
    return "".join(f"{folded}\r\n" for line in lines for folded in _fold(line))
