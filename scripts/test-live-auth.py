"""Opt-in integration check. Creates one synthetic user; deletes its test sleep record.

No real health data, passwords or JWTs are printed or saved. The test user remains
because the current backend has no account deletion endpoint.
"""
import argparse
import http.cookiejar
import json
import os
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-test-account", action="store_true", required=True)
    args = parser.parse_args()
    base = os.environ["SLEEP_API_BASE_URL"].rstrip("/")
    code = os.environ.get("SLEEP_GATEWAY_SHARE_CODE", "")
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    if code:
        origin = urllib.parse.urlsplit(base)
        entry = urllib.parse.urlunsplit((origin.scheme, origin.netloc, "/", urllib.parse.urlencode({"sharecode": code}), ""))
        with opener.open(entry, timeout=25) as response:
            assert response.status == 200

    def call(path, method="GET", body=None, token=None, expected=200):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
            if code:
                headers["X-Auth-Token"] = "Bearer " + token
        request = urllib.request.Request(base + path, method=method, headers=headers,
                                         data=json.dumps(body).encode() if body is not None else None)
        try:
            with opener.open(request, timeout=25) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        assert status == expected, f"{method} {path}: expected {expected}, got {status}"
        print(f"PASS {method} {path} {status}")
        return json.loads(raw) if raw else {}

    name = "ios_check_" + str(int(time.time())) + secrets.token_hex(2)
    email, password = name + "@example.com", secrets.token_urlsafe(24)
    user = {"username": name, "email": email, "password": password}
    call("/auth/register", "POST", user, expected=201)
    call("/auth/register", "POST", user, expected=409)
    call("/auth/register", "POST", {**user, "username": name + "x"}, expected=409)
    call("/auth/login", "POST", {"email": email, "password": "wrong-password"}, expected=401)
    login = call("/auth/login", "POST", {"email": email, "password": password})
    token = login["access_token"]
    assert login["token_type"] == "bearer" and login["expire_at"] > time.time()
    me = call("/auth/me", token=token)
    assert me["email"] == email and "password" not in me
    record_id = None
    try:
        payload = {"record_date": "2026-11-05", "sleep_start_time": "2026-11-04 23:00:00",
                   "sleep_end_time": "2026-11-05 07:00:00", "total_duration_minutes": 450,
                   "deep_sleep_minutes": 90, "light_sleep_minutes": 270, "rem_minutes": 90,
                   "awake_times": 2, "isi_score": 3, "ais_score": 2,
                   "notes": "AUTOMATED INTEGRATION TEST - synthetic data, delete after check"}
        record = call("/health/sleep-record", "POST", payload, token=token, expected=201)
        record_id = record["id"]
        assert record["user_id"] == me["id"] and record["isi_score"] == 3 and record["ais_score"] == 2
        call("/health/sleep-record/" + str(record_id), token=token)
    finally:
        if record_id:
            call("/health/sleep-record/" + str(record_id), "DELETE", token=token)
    call("/auth/logout", "POST", token=token)
    call("/auth/me", token=token, expected=401)
    call("/health/sleep-record", "POST", payload, token=token, expected=401)
    print("Synthetic test account retained:", name)


if __name__ == "__main__":
    main()
