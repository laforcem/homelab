"""Minimal CalDAV client: list, put, delete objects in one calendar collection."""
import base64
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

PREFIX = "ppld-"
TIMEOUT = 30
_PROPFIND_BODY = (
    b'<?xml version="1.0"?>'
    b'<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/></d:prop></d:propfind>'
)


class CalDavError(Exception):
    pass


class CalDavClient:
    def __init__(self, calendar_url: str, username: str, password: str):
        self.base = calendar_url if calendar_url.endswith("/") else calendar_url + "/"
        token = base64.b64encode(f"{username}:{password}".encode()).decode()
        self._auth = f"Basic {token}"

    def _request(self, method, url, body=None, headers=None, ok=(200,)) -> bytes:
        req = urllib.request.Request(
            url, data=body, method=method, headers={"Authorization": self._auth, **(headers or {})}
        )
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                status, payload = resp.status, resp.read()
        except urllib.error.HTTPError as e:
            status, payload = e.code, b""
        except (urllib.error.URLError, TimeoutError) as e:
            raise CalDavError(f"{method} failed: {type(e).__name__}") from None
        if status not in ok:
            # Last path segment only: the full path contains the account name.
            last = urllib.parse.urlsplit(url).path.rsplit("/", 1)[-1] or "/"
            raise CalDavError(f"{method} {last} -> HTTP {status}")
        return payload

    def list_managed(self) -> set[str]:
        body = self._request(
            "PROPFIND", self.base, _PROPFIND_BODY,
            {"Depth": "1", "Content-Type": "application/xml"}, ok=(207,),
        )
        names = set()
        for href in ET.fromstring(body).iter("{DAV:}href"):
            name = urllib.parse.unquote(href.text or "").rstrip("/").rsplit("/", 1)[-1]
            if name.startswith(PREFIX) and name.endswith(".ics"):
                names.add(name)
        return names

    def put(self, filename: str, ics: str) -> None:
        self._request(
            "PUT", self.base + filename, ics.encode("utf-8"),
            {"Content-Type": "text/calendar; charset=utf-8"}, ok=(200, 201, 204),
        )

    def delete(self, filename: str) -> None:
        self._request("DELETE", self.base + filename, ok=(200, 204, 404))
