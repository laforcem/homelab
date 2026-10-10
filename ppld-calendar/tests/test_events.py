import json
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

from ppld_calendar.events import Event, checkout_to_event, local_date, render_ics

FIXTURE = json.loads((Path(__file__).parent / "fixtures" / "checkouts.json").read_text())


class LocalDateTests(unittest.TestCase):
    def test_due_time_before_utc_midnight_is_previous_utc_day_locally(self):
        # 23:59:59 MDT on Oct 12 is 05:59:59Z on Oct 13.
        self.assertEqual(local_date("2026-10-13T05:59:59Z"), date(2026, 10, 12))

    def test_dst_end_boundary(self):
        # DST ends Nov 1 2026; this instant is still Oct 31 in Denver.
        self.assertEqual(local_date("2026-11-01T05:59:59Z"), date(2026, 10, 31))

    def test_winter_offset(self):
        self.assertEqual(local_date("2026-12-15T06:59:59Z"), date(2026, 12, 14))

    def test_midday_utc_same_day(self):
        self.assertEqual(local_date("2026-10-11T20:02:55Z"), date(2026, 10, 11))

    def test_unexpected_format_raises(self):
        with self.assertRaises(ValueError):
            local_date("2026-10-13")


class CheckoutToEventTests(unittest.TestCase):
    def test_renewable_physical_item(self):
        ev = checkout_to_event(FIXTURE[0])
        self.assertEqual(ev.uid, "ppld-checkout-100001@homelab")
        self.assertEqual(ev.filename, "ppld-checkout-100001.ics")
        self.assertEqual(ev.summary, "Due: Test Book One")
        self.assertEqual(ev.day, date(2026, 10, 12))
        self.assertEqual(ev.description, "Renewable (1 of 2 renewals left)\nBook via gates")
        self.assertEqual(ev.stamp, datetime(2026, 9, 20, 19, 42, 58, tzinfo=timezone.utc))

    def test_not_renewable_physical_item(self):
        ev = checkout_to_event(FIXTURE[1])
        self.assertEqual(ev.day, date(2026, 10, 31))
        self.assertEqual(ev.description, "Not renewable\nBook via gates")

    def test_overdrive_item_without_renewable_key(self):
        ev = checkout_to_event(FIXTURE[2])
        self.assertEqual(ev.uid, "ppld-checkout-00000000-0000-0000-0000-000000000003@homelab")
        self.assertEqual(ev.description, "Not renewable\nEaudiobook via overdrive")

    def test_unsafe_id_rejected(self):
        bad = dict(FIXTURE[0], id="../evil")
        with self.assertRaises(ValueError):
            checkout_to_event(bad)

    def test_trailing_newline_id_rejected(self):
        bad = dict(FIXTURE[0], id="100001\n")
        with self.assertRaises(ValueError):
            checkout_to_event(bad)


class RenderIcsTests(unittest.TestCase):
    def test_all_day_event_with_alarm(self):
        ics = render_ics(checkout_to_event(FIXTURE[1]))
        self.assertTrue(ics.startswith("BEGIN:VCALENDAR\r\n"))
        self.assertTrue(ics.endswith("END:VCALENDAR\r\n"))
        self.assertIn("UID:ppld-checkout-100002@homelab\r\n", ics)
        self.assertIn("DTSTAMP:20261010T183403Z\r\n", ics)
        self.assertIn("DTSTART;VALUE=DATE:20261031\r\n", ics)
        self.assertIn("DTEND;VALUE=DATE:20261101\r\n", ics)
        self.assertIn("TRIGGER:-PT15H\r\n", ics)

    def test_text_is_escaped(self):
        ics = render_ics(checkout_to_event(FIXTURE[1]))
        self.assertIn("SUMMARY:Due: Test Book Two\\, A Novel\r\n", ics)
        self.assertIn("DESCRIPTION:Not renewable\\nBook via gates\r\n", ics)

    def test_control_characters_become_spaces(self):
        ev = checkout_to_event(dict(FIXTURE[1], resource=dict(FIXTURE[1]["resource"], title="A\rB\x07C")))
        ics = render_ics(ev)
        self.assertIn("SUMMARY:Due: A B C\r\n", ics)
        self.assertNotIn("\x07", ics)
        self.assertEqual(ics.count("\r"), ics.count("\r\n"))

    def test_long_lines_fold_at_75_octets_and_unfold_losslessly(self):
        title = "É" * 60 + " " + "x" * 80
        ev = Event(
            uid="ppld-checkout-1@homelab",
            filename="ppld-checkout-1.ics",
            summary=f"Due: {title}",
            description="d",
            day=date(2026, 10, 12),
            stamp=datetime(2026, 9, 20, tzinfo=timezone.utc),
        )
        ics = render_ics(ev)
        for line in ics.split("\r\n"):
            self.assertLessEqual(len(line.encode("utf-8")), 75)
        self.assertIn(f"SUMMARY:Due: {title}\r\n", ics.replace("\r\n ", ""))


if __name__ == "__main__":
    unittest.main()
