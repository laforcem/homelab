#!/usr/bin/env python3
"""Send a Telegram alert when icloudpd's 2FA/session auth is expiring.

Invoked directly (no argv) by icloudpd's --notification-script flag. Uses
only the Python standard library since the icloudpd runtime image has no
curl/wget installed, but always ships python3 as its own base.
"""
import os
import sys
import urllib.parse
import urllib.request

REQUIRED_VARS = ("TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID", "ICLOUDPD_ACCOUNT_NAME")


def require_env(name):
    value = os.environ.get(name)
    if not value:
        print(f"{name}: parameter not set or empty", file=sys.stderr)
        sys.exit(1)
    return value


def main():
    env = {name: require_env(name) for name in REQUIRED_VARS}

    url = f"https://api.telegram.org/bot{env['TELEGRAM_BOT_TOKEN']}/sendMessage"
    text = (
        f"icloudpd ({env['ICLOUDPD_ACCOUNT_NAME']}): 2FA/session auth is "
        "expiring soon — open the webui to re-authenticate."
    )
    data = urllib.parse.urlencode(
        {"chat_id": env["TELEGRAM_CHAT_ID"], "text": text}
    ).encode()

    request = urllib.request.Request(url, data=data, method="POST")
    with urllib.request.urlopen(request) as response:
        response.read()


if __name__ == "__main__":
    main()
