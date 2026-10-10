import json
import unittest
from pathlib import Path
from unittest import mock

from ppld_calendar import main as app
from ppld_calendar.ppld import PpldError

CHECKOUTS = json.loads((Path(__file__).parent / "fixtures" / "checkouts.json").read_text())
HC = "https://hc.example.test/abc"
ENV = {
    "PPLD_CARD_NUMBER": "12345",
    "PPLD_PIN": "s3cret",
    "CALDAV_USERNAME": "someone@example.com",
    "CALDAV_APP_PASSWORD": "app-pw",
    "CALDAV_CALENDAR_URL": "https://caldav.example.test/cal/",
    "HEALTHCHECK_URL": HC,
}


class FakeClient:
    def __init__(self):
        self.puts, self.deletes = [], []

    def list_managed(self):
        return {"ppld-checkout-stale.ics"}

    def put(self, filename, ics):
        self.puts.append(filename)

    def delete(self, filename):
        self.deletes.append(filename)


class MainTests(unittest.TestCase):
    def run_main(self, env=ENV, checkouts=CHECKOUTS, holds=(), login_error=None):
        fake = FakeClient()
        login = mock.Mock(side_effect=login_error) if login_error else mock.Mock(return_value="tok")
        with mock.patch.object(app.ppld, "login", login), \
             mock.patch.object(app.ppld, "fetch_checkouts", return_value=checkouts), \
             mock.patch.object(app.ppld, "fetch_holds", return_value=list(holds)), \
             mock.patch.object(app, "CalDavClient", return_value=fake) as client_cls, \
             mock.patch.object(app, "ping") as ping:
            code = app.main(env)
        return code, fake, ping, login, client_cls

    def test_success_syncs_and_pings_success(self):
        code, fake, ping, _, client_cls = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(len(fake.puts), 3)
        self.assertEqual(fake.deletes, ["ppld-checkout-stale.ics"])
        ping.assert_called_once_with(HC)
        client_cls.assert_called_once_with(
            "https://caldav.example.test/cal/", "someone@example.com", "app-pw"
        )

    def test_empty_checkouts_is_valid_and_clears_calendar(self):
        code, fake, _, _, _ = self.run_main(checkouts=[])
        self.assertEqual(code, 0)
        self.assertEqual(fake.puts, [])
        self.assertEqual(fake.deletes, ["ppld-checkout-stale.ics"])

    def test_ppld_failure_changes_nothing_and_pings_fail(self):
        code, fake, ping, _, _ = self.run_main(login_error=PpldError("HTTP 401 from /token"))
        self.assertEqual(code, 1)
        self.assertEqual((fake.puts, fake.deletes), ([], []))
        ping.assert_called_once_with(HC, "/fail")

    def test_missing_env_fails_before_login(self):
        env = {k: v for k, v in ENV.items() if k != "PPLD_PIN"}
        code, _, ping, login, _ = self.run_main(env=env)
        self.assertEqual(code, 1)
        login.assert_not_called()
        ping.assert_called_once_with(HC, "/fail")

    def test_dry_run_writes_nothing(self):
        code, fake, _, _, _ = self.run_main(env={**ENV, "DRY_RUN": "1"})
        self.assertEqual(code, 0)
        self.assertEqual((fake.puts, fake.deletes), ([], []))

    def test_nonempty_holds_do_not_fail_the_run(self):
        code, _, _, _, _ = self.run_main(holds=[{"someField": 1}])
        self.assertEqual(code, 0)

    def test_holds_fetch_failure_is_ignored_and_checkouts_sync(self):
        fake = FakeClient()
        with mock.patch.object(app.ppld, "login", return_value="tok"), \
             mock.patch.object(app.ppld, "fetch_checkouts", return_value=CHECKOUTS), \
             mock.patch.object(app.ppld, "fetch_holds", side_effect=PpldError("HTTP 500 from /holds")), \
             mock.patch.object(app, "CalDavClient", return_value=fake), \
             mock.patch.object(app, "ping") as ping:
            code = app.main(ENV)
        self.assertEqual(code, 0)
        self.assertEqual(len(fake.puts), 3)
        ping.assert_called_once_with(HC)

    def test_holds_dict_does_not_fail_run_and_logs_keys_only(self):
        fake = FakeClient()
        with mock.patch.object(app.ppld, "login", return_value="tok"), \
             mock.patch.object(app.ppld, "fetch_checkouts", return_value=CHECKOUTS), \
             mock.patch.object(app.ppld, "fetch_holds", return_value={"k": "secretvalue"}), \
             mock.patch.object(app, "CalDavClient", return_value=fake), \
             mock.patch.object(app, "ping"), \
             self.assertLogs("ppld-calendar", level="INFO") as logs:
            code = app.main(ENV)
        self.assertEqual(code, 0)
        self.assertEqual(len(fake.puts), 3)
        out = "\n".join(logs.output)
        self.assertIn("'k'", out)
        self.assertNotIn("secretvalue", out)

    def test_unexpected_exception_text_is_not_logged(self):
        with mock.patch.object(app.ppld, "login", side_effect=ValueError("boom someone@example.com")), \
             mock.patch.object(app, "CalDavClient"), \
             mock.patch.object(app, "ping") as ping, \
             self.assertLogs("ppld-calendar", level="INFO") as logs:
            code = app.main(ENV)
        self.assertEqual(code, 1)
        ping.assert_called_once_with(HC, "/fail")
        out = "\n".join(logs.output)
        self.assertNotIn("someone@example.com", out)
        self.assertIn("ValueError", out)

    def test_bad_checkout_record_fails_closed(self):
        bad = [dict(CHECKOUTS[0], dueDate="not-a-date")]
        code, fake, ping, _, _ = self.run_main(checkouts=bad)
        self.assertEqual(code, 1)
        self.assertEqual((fake.puts, fake.deletes), ([], []))
        ping.assert_called_once_with(HC, "/fail")


if __name__ == "__main__":
    unittest.main()
