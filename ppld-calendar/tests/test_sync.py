import unittest
from datetime import date, datetime, timezone

from ppld_calendar.caldav import CalDavError
from ppld_calendar.events import Event
from ppld_calendar.sync import run_sync


def ev(n):
    return Event(
        uid=f"ppld-checkout-{n}@homelab",
        filename=f"ppld-checkout-{n}.ics",
        summary=f"Due: Book {n}",
        description="d",
        day=date(2026, 10, 12),
        stamp=datetime(2026, 9, 20, tzinfo=timezone.utc),
    )


class FakeClient:
    def __init__(self, existing=(), fail_put=(), fail_list=False):
        self.existing = set(existing)
        self.fail_put = set(fail_put)
        self.fail_list = fail_list
        self.puts, self.deletes = [], []

    def list_managed(self):
        if self.fail_list:
            raise CalDavError("PROPFIND / -> HTTP 500")
        return set(self.existing)

    def put(self, filename, ics):
        if filename in self.fail_put:
            raise CalDavError(f"PUT {filename} -> HTTP 500")
        self.puts.append((filename, ics))

    def delete(self, filename):
        self.deletes.append(filename)


class RunSyncTests(unittest.TestCase):
    def test_puts_every_desired_event(self):
        c = FakeClient(existing={"ppld-checkout-1.ics"})
        r = run_sync([ev(1), ev(2)], c)
        self.assertEqual([f for f, _ in c.puts], ["ppld-checkout-1.ics", "ppld-checkout-2.ics"])
        self.assertEqual((r.put, r.deleted, r.errors), (2, 0, []))
        self.assertIn("BEGIN:VCALENDAR", c.puts[0][1])

    def test_deletes_stale_managed_objects(self):
        c = FakeClient(existing={"ppld-checkout-1.ics", "ppld-checkout-9.ics"})
        r = run_sync([ev(1)], c)
        self.assertEqual(c.deletes, ["ppld-checkout-9.ics"])
        self.assertEqual(r.deleted, 1)

    def test_empty_desired_removes_all_managed(self):
        c = FakeClient(existing={"ppld-checkout-1.ics", "ppld-checkout-2.ics"})
        r = run_sync([], c)
        self.assertEqual(sorted(c.deletes), ["ppld-checkout-1.ics", "ppld-checkout-2.ics"])
        self.assertEqual(r.deleted, 2)

    def test_dry_run_writes_nothing_but_counts(self):
        c = FakeClient(existing={"ppld-checkout-9.ics"})
        r = run_sync([ev(1)], c, dry_run=True)
        self.assertEqual((c.puts, c.deletes), ([], []))
        self.assertEqual((r.put, r.deleted), (1, 1))

    def test_per_event_error_is_recorded_and_run_continues(self):
        c = FakeClient(existing={"ppld-checkout-9.ics"}, fail_put={"ppld-checkout-1.ics"})
        r = run_sync([ev(1), ev(2)], c)
        self.assertEqual([f for f, _ in c.puts], ["ppld-checkout-2.ics"])
        self.assertEqual(c.deletes, ["ppld-checkout-9.ics"])
        self.assertEqual(len(r.errors), 1)
        self.assertIn("ppld-checkout-1.ics", r.errors[0])

    def test_list_failure_propagates_before_any_write(self):
        c = FakeClient(fail_list=True)
        with self.assertRaises(CalDavError):
            run_sync([ev(1)], c)
        self.assertEqual((c.puts, c.deletes), ([], []))


if __name__ == "__main__":
    unittest.main()
