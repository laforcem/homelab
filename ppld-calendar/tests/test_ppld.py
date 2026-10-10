import io
import json
import unittest
import urllib.error
from unittest import mock

from ppld_calendar import ppld


def _resp(payload):
    cm = mock.MagicMock()
    cm.__enter__.return_value = io.BytesIO(json.dumps(payload).encode())
    return cm


class LoginTests(unittest.TestCase):
    def test_sends_password_grant_and_returns_token(self):
        with mock.patch("urllib.request.urlopen", return_value=_resp({"access_token": "tok"})) as op:
            token = ppld.login("12345", "s3cret")
        self.assertEqual(token, "tok")
        req = op.call_args[0][0]
        self.assertEqual(req.full_url, ppld.TOKEN_URL)
        body = req.data.decode()
        self.assertIn("grant_type=password", body)
        self.assertIn("client_id=convergence", body)
        self.assertIn("username=12345", body)
        self.assertEqual(req.get_header("Content-type"), "application/x-www-form-urlencoded")

    def test_http_error_does_not_leak_credentials(self):
        err = urllib.error.HTTPError(ppld.TOKEN_URL, 401, "Unauthorized", {}, None)
        with mock.patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(ppld.PpldError) as ctx:
                ppld.login("12345", "s3cret")
        self.assertIn("401", str(ctx.exception))
        self.assertNotIn("s3cret", str(ctx.exception))
        self.assertNotIn("12345", str(ctx.exception))

    def test_missing_access_token_raises(self):
        with mock.patch("urllib.request.urlopen", return_value=_resp({"foo": "bar"})):
            with self.assertRaises(ppld.PpldError):
                ppld.login("1", "2")


class FetchTests(unittest.TestCase):
    def test_checkouts_sends_required_headers(self):
        with mock.patch("urllib.request.urlopen", return_value=_resp([{"id": "1"}])) as op:
            result = ppld.fetch_checkouts("tok")
        self.assertEqual(result, [{"id": "1"}])
        req = op.call_args[0][0]
        self.assertTrue(req.full_url.endswith("/patrons/me/checkouts"))
        self.assertEqual(req.get_header("Authorization"), "Bearer tok")
        self.assertEqual(req.get_header("Api-version"), "1")
        self.assertEqual(req.get_header("Iii-customer-domain"), "ppld.na5.iiivega.com")

    def test_checkouts_non_list_raises(self):
        with mock.patch("urllib.request.urlopen", return_value=_resp({"error": "x"})):
            with self.assertRaises(ppld.PpldError):
                ppld.fetch_checkouts("tok")

    def test_holds_empty_list(self):
        with mock.patch("urllib.request.urlopen", return_value=_resp([])):
            self.assertEqual(ppld.fetch_holds("tok"), [])

    def test_holds_dict_is_returned_as_is(self):
        with mock.patch("urllib.request.urlopen", return_value=_resp({"k": 1})):
            self.assertEqual(ppld.fetch_holds("tok"), {"k": 1})

    def test_holds_http_error_raises_ppld_error(self):
        err = urllib.error.HTTPError("u", 500, "Err", {}, None)
        with mock.patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(ppld.PpldError):
                ppld.fetch_holds("tok")

    def test_fetch_http_error_raises_ppld_error(self):
        err = urllib.error.HTTPError("u", 403, "Forbidden", {}, None)
        with mock.patch("urllib.request.urlopen", side_effect=err):
            with self.assertRaises(ppld.PpldError):
                ppld.fetch_checkouts("tok")


if __name__ == "__main__":
    unittest.main()
