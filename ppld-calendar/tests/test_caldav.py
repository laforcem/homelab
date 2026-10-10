import unittest
import urllib.error
from unittest import mock

from ppld_calendar.caldav import CalDavClient, CalDavError

URL = "https://caldav.example.test/dav/calendars/user/someone@example.com/library/"

MULTISTATUS = b"""<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/calendars/user/someone@example.com/library/</d:href></d:response>
  <d:response><d:href>/dav/calendars/user/someone@example.com/library/ppld-checkout-100001.ics</d:href></d:response>
  <d:response><d:href>/dav/calendars/user/someone@example.com/library/other-event.ics</d:href></d:response>
  <d:response><d:href>/dav/calendars/user/someone@example.com/library/ppld-checkout-abc%2D1.ics</d:href></d:response>
</d:multistatus>"""


def _ok(status=207, body=b""):
    cm = mock.MagicMock()
    resp = cm.__enter__.return_value
    resp.status = status
    resp.read.return_value = body
    return cm


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.client = CalDavClient(URL, "someone@example.com", "app-pw")

    def test_list_managed_filters_to_ppld_ics(self):
        with mock.patch("urllib.request.urlopen", return_value=_ok(207, MULTISTATUS)) as op:
            names = self.client.list_managed()
        self.assertEqual(names, {"ppld-checkout-100001.ics", "ppld-checkout-abc-1.ics"})
        req = op.call_args[0][0]
        self.assertEqual(req.get_method(), "PROPFIND")
        self.assertEqual(req.full_url, URL)
        self.assertEqual(req.get_header("Depth"), "1")
        self.assertTrue(req.get_header("Authorization").startswith("Basic "))

    def test_base_url_gets_trailing_slash(self):
        client = CalDavClient(URL.rstrip("/"), "u", "p")
        with mock.patch("urllib.request.urlopen", return_value=_ok(201)) as op:
            client.put("ppld-checkout-1.ics", "BEGIN:VCALENDAR\r\n")
        self.assertEqual(op.call_args[0][0].full_url, URL + "ppld-checkout-1.ics")

    def test_put_sends_ics_body(self):
        with mock.patch("urllib.request.urlopen", return_value=_ok(201)) as op:
            self.client.put("ppld-checkout-1.ics", "BEGIN:VCALENDAR\r\n")
        req = op.call_args[0][0]
        self.assertEqual(req.get_method(), "PUT")
        self.assertEqual(req.data, b"BEGIN:VCALENDAR\r\n")
        self.assertEqual(req.get_header("Content-type"), "text/calendar; charset=utf-8")

    def test_delete_treats_404_as_success(self):
        err = urllib.error.HTTPError(URL, 404, "Not Found", {}, None)
        with mock.patch("urllib.request.urlopen", side_effect=err) as op:
            self.client.delete("ppld-checkout-1.ics")
        self.assertEqual(op.call_args[0][0].get_method(), "DELETE")

    def test_error_message_has_no_user_path_or_password(self):
        err = urllib.error.HTTPError(URL, 403, "Forbidden", {}, None)
        with mock.patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(CalDavError) as ctx:
                self.client.put("ppld-checkout-1.ics", "x")
        msg = str(ctx.exception)
        self.assertIn("403", msg)
        self.assertIn("ppld-checkout-1.ics", msg)
        self.assertNotIn("someone@example.com", msg)
        self.assertNotIn("app-pw", msg)

    def test_list_unexpected_status_raises(self):
        with mock.patch("urllib.request.urlopen", return_value=_ok(200, b"")):
            with self.assertRaises(CalDavError):
                self.client.list_managed()


if __name__ == "__main__":
    unittest.main()
