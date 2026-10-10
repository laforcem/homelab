"""PPLD (Innovative Vega) patron API client. Undocumented; observed from the catalog SPA."""
import json
import urllib.error
import urllib.parse
import urllib.request

TOKEN_URL = "https://auth.na5.iiivega.com/auth/realms/ppld/protocol/openid-connect/token"
API_BASE = "https://na5.iiivega.com/api/search-result/patrons/me"
CLIENT_ID = "convergence"
API_HEADERS = {"api-version": "1", "iii-customer-domain": "ppld.na5.iiivega.com"}
TIMEOUT = 30


class PpldError(Exception):
    pass


def _get_json(url: str, headers: dict, data: bytes | None = None):
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        # Deliberately not reading the body or chaining: neither may echo credentials.
        raise PpldError(f"HTTP {e.code} from {urllib.parse.urlsplit(url).path}") from None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        raise PpldError(f"request failed: {type(e).__name__}") from None


def login(card: str, pin: str) -> str:
    body = urllib.parse.urlencode(
        {"grant_type": "password", "client_id": CLIENT_ID, "username": card, "password": pin}
    ).encode()
    data = _get_json(TOKEN_URL, {"Content-Type": "application/x-www-form-urlencoded"}, body)
    token = data.get("access_token") if isinstance(data, dict) else None
    if not token:
        raise PpldError("token response had no access_token")
    return token


def _authed_get(path: str, token: str):
    return _get_json(f"{API_BASE}/{path}", {**API_HEADERS, "Authorization": f"Bearer {token}"})


def fetch_checkouts(token: str) -> list[dict]:
    data = _authed_get("checkouts", token)
    if not isinstance(data, list):
        raise PpldError("checkouts response was not a list")
    return data


def fetch_holds(token: str):
    """Holds are informational only; the shape is unverified, so return it as-is."""
    return _authed_get("holds", token)
