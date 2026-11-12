"""Mirror Pinterest boards into Immich albums, dated by when each pin was saved.

BOARDS is a JSON object of album name -> board URL. Every album belongs to the
Immich user who owns IMMICH_API_KEY.

Safe to re-run. gallery-dl's archive skips images it already fetched, Immich
answers a re-upload with the existing asset (status DUPLICATE), and each
board's state.json records which images are already uploaded, in the album
and dated.

Everything is keyed on the image hash (gallery-dl's {filename}), not the pin id:
Pinterest returns different pin ids to signed-in and signed-out requests.
"""

import email.utils
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

BOARDS = json.loads(os.environ["BOARDS"])
IMMICH = os.environ["IMMICH_URL"].rstrip("/")
KEY = os.environ["IMMICH_API_KEY"]
DATA = pathlib.Path(os.environ.get("DATA_DIR", "/data"))
# gallery-dl rewrites its cookies file on exit, and the Secret mount is
# read-only, so it works on a copy.
COOKIES = pathlib.Path("/tmp/pinterest-cookies.txt")
shutil.copyfile(os.environ["PINTEREST_COOKIES_FILE"], COOKIES)


def gallery_dl(*args):
    return subprocess.run(
        ["gallery-dl", "--cookies", str(COOKIES), *args],
        check=True, stdout=subprocess.PIPE, text=True,
    ).stdout


def immich(method, path, body=None, headers=None):
    req = urllib.request.Request(
        IMMICH + path, data=body, method=method,
        headers={"x-api-key": KEY, "accept": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def immich_json(method, path, obj):
    return immich(method, path, json.dumps(obj).encode(),
                  {"content-type": "application/json"})


def pin_saved_at(pin_id):
    """A board pin's created_at is when it was saved to the board."""
    import http.cookiejar
    jar = http.cookiejar.MozillaCookieJar(str(COOKIES))
    jar.load(ignore_discard=True, ignore_expires=True)
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    data = json.dumps({"options": {"id": pin_id, "field_set_key": "detailed"}})
    req = urllib.request.Request(
        "https://www.pinterest.com/resource/PinResource/get/?data="
        + urllib.parse.quote(data),
        headers={"accept": "application/json", "user-agent": "Mozilla/5.0",
                 "x-pinterest-pws-handler": "www/pin/[id].js"},
    )
    with opener.open(req, timeout=30) as r:
        created = json.load(r)["resource_response"]["data"]["created_at"]
    return email.utils.parsedate_to_datetime(created)


def upload(path, when):
    """POST /assets as multipart; returns the asset id, new or existing."""
    blob = path.read_bytes()
    checksum = hashlib.sha1(blob).hexdigest()
    # Ask first. Sent straight to immich-server (no proxy buffering the body),
    # a duplicate upload gets its answer before the body is fully sent, and
    # the connection closes under a large file: Broken pipe.
    known = immich_json("POST", "/assets/bulk-upload-check",
                        {"assets": [{"id": "0", "checksum": checksum}]})["results"][0]
    if known.get("assetId"):
        return known["assetId"]
    boundary = uuid.uuid4().hex
    stamp = when.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    parts = []
    for name, value in (("fileCreatedAt", stamp), ("fileModifiedAt", stamp),
                        ("filename", path.name)):
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; '
                     f'name="{name}"\r\n\r\n{value}\r\n'.encode())
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="assetData"; '
                 f'filename="{path.name}"\r\nContent-Type: application/octet-stream'
                 '\r\n\r\n'.encode() + blob + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    res = immich("POST", "/assets", b"".join(parts), {
        "content-type": f"multipart/form-data; boundary={boundary}",
        "x-immich-checksum": checksum,
    })
    return res["id"]


def add_image(path, pin_ids, album_id):
    # The same image saved twice: date it by the first save.
    when = min(pin_saved_at(p) for p in pin_ids)
    asset = upload(path, when)
    immich_json("PUT", f"/albums/{album_id}/assets", {"ids": [asset]})
    # Set the date explicitly too: a file's own EXIF date would beat
    # fileCreatedAt. Archived keeps it off the owner's timeline; albums
    # still show archived photos.
    immich_json("PUT", f"/assets/{asset}",
                {"dateTimeOriginal": when.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
                 "visibility": "archive"})
    return asset


class CookiesExpired(Exception):
    pass


def sync_board(album_name, board_url, albums):
    """Returns the image failures; raises if the board can't be read at all."""
    # Per-board directory, named by the board's URL slug.
    data = DATA / board_url.rstrip("/").rsplit("/", 1)[-1]
    files, state_file = data / "files", data / "state.json"

    # One crawl for metadata. Signed out, Pinterest hides some pins and
    # scrambles pin ids, so non-numeric ids mean the session has expired.
    board = {}
    for entry in json.loads(gallery_dl("-j", board_url)):
        if entry[0] == 3:
            meta = entry[2]
            board.setdefault(meta["filename"], []).append(str(meta["id"]))
    if not board:
        raise ValueError("board returned no images")
    if not all(i.isdigit() for ids in board.values() for i in ids):
        raise CookiesExpired

    files.mkdir(parents=True, exist_ok=True)
    gallery_dl("-D", str(files), "--download-archive", str(data / "archive.sqlite3"),
               "-f", "{filename}.{extension}", "-o", "archive-format=pin_{filename}",
               board_url)

    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    album_id = albums.get(album_name) or immich_json(
        "POST", "/albums", {"albumName": album_name})["id"]

    added, failed = 0, []
    for image, pin_ids in board.items():
        if image in state:
            continue
        found = sorted(files.glob(image + ".*"))
        if not found:
            failed.append(f"{image}: not downloaded")
            continue
        # Every step is idempotent, so one retry is safe. It covers the
        # occasional dropped connection (seen once in 321 uploads in testing).
        for attempt in (1, 2):
            try:
                asset = add_image(found[0], pin_ids, album_id)
                break
            except (urllib.error.URLError, KeyError, ValueError) as e:
                error = e
        else:
            failed.append(f"{image}: {error}")
            continue
        state[image] = asset
        state_file.write_text(json.dumps(state))
        added += 1

    print(f"{album_name}: {len(board)} images; added {added}; {len(state)} in album")
    return failed


def main():
    albums = {a["albumName"]: a["id"] for a in immich("GET", "/albums")}
    failed = []
    # One board failing doesn't stop the others; the run still fails at the end.
    for album_name, board_url in BOARDS.items():
        try:
            failed += [f"{album_name}: {f}" for f in
                       sync_board(album_name, board_url, albums)]
        except CookiesExpired:
            sys.exit("Pinterest cookies have expired: re-export them into Bitwarden")
        except (subprocess.CalledProcessError, urllib.error.URLError,
                KeyError, ValueError) as e:
            failed.append(f"{album_name}: board failed: {e}")
    if failed:
        print("\n".join(failed), file=sys.stderr)
        sys.exit(f"{len(failed)} failure(s)")


if __name__ == "__main__":
    main()
