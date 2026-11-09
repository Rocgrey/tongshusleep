"""Opt-in integration check. Creates phone and legacy email test users.

No real health data, passwords or JWTs are printed or saved. The test user remains
and synthetic steps remain because the backend has no deletion endpoints for them.
The synthetic sleep record is deleted after checking the contract.
"""
import argparse
import http.cookiejar
import json
import os
import secrets
import time
from datetime import datetime, timedelta, timezone
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
    phone, password = "139" + str(secrets.randbelow(10**8)).zfill(8), secrets.token_urlsafe(24)
    user = {"username": name, "phone": phone, "password": password}
    call("/auth/register", "POST", user, expected=201)
    call("/auth/register", "POST", user, expected=409)
    call("/auth/register", "POST", {**user, "username": name + "x"}, expected=409)
    call("/auth/login", "POST", {"phone": phone, "password": "wrong-password"}, expected=401)
    login = call("/auth/login", "POST", {"phone": phone, "password": password})
    token = login["access_token"]
    assert login["token_type"] == "bearer" and login["expire_at"] > time.time()
    me = call("/auth/me", token=token)
    assert me["phone"] == phone and me.get("email") is None and "password" not in me
    # Existing email-only accounts retain their own identity; contacts never merge users.
    legacy_name = name + "e"
    email = legacy_name + "@example.com"
    call("/auth/register", "POST", {"username": legacy_name, "email": email, "password": password}, expected=201)
    legacy = call("/auth/login", "POST", {"email": email, "password": password})
    legacy_token = legacy["access_token"]
    legacy_me = call("/auth/me", token=legacy_token)
    assert legacy_me["id"] != me["id"] and legacy_me["email"] == email
    now = datetime.now(timezone(timedelta(hours=8)))
    today, yesterday, missing = [ (now - timedelta(days=d)).strftime("%Y-%m-%d") for d in (0, 1, 2)]
    stamp = now.strftime("%Y-%m-%d %H:%M:%S")
    base_step = {"record_date": today, "steps": 1000, "source": "healthkit", "source_id": "synthetic-integration-check", "data_time": stamp, "timezone": "Asia/Shanghai"}
    path = "/health/step-record"
    first_step = call(path, "POST", base_step, token=token)
    assert first_step["record"]["user_id"] == me["id"]
    repeat = call(path, "POST", base_step, token=token)
    assert repeat["record_id"] == first_step["record_id"]
    updated = {**base_step, "steps": 1500, "data_time": (now + timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S")}
    call(path, "POST", updated, token=token)
    stale = call(path, "POST", {**base_step, "steps": 100}, token=token)
    assert stale["applied"] is False
    call(path, "POST", {**base_step, "steps": 9999, "source": "wearable"}, token=token)
    call(path, "POST", {**base_step, "steps": 8888, "source": "phone"}, token=token)
    call(path, "POST", {**base_step, "steps": 0, "record_date": yesterday}, token=token)
    query = "/health/step-records?" + urllib.parse.urlencode({"start_date": missing, "end_date": today})
    cloud = call(query, token=token)
    assert cloud["summary"]["total_steps"] == 1500
    assert cloud["summary"]["days_with_record"] == 2
    assert cloud["summary"]["days_real_zero"] == 1 and cloud["summary"]["days_missing"] == 1
    assert cloud["summary"]["avg_steps"] == 750
    assert next(d for d in cloud["days"] if d["record_date"] == today)["source"] == "healthkit"
    assert call(query, token=legacy_token)["summary"]["days_with_record"] == 0
    call("/auth/logout", "POST", token=legacy_token)
    record_id = None
    try:
        payload = {"record_date": "2026-11-05", "sleep_start_time": "2026-11-04 23:00:00",
                   "sleep_end_time": "2026-11-05 07:00:00", "total_duration_minutes": 450,
                   "deep_sleep_minutes": 90, "light_sleep_minutes": 270, "rem_minutes": 90,
                   "awake_times": 2, "ais_score": 2,
                   "notes": "AUTOMATED INTEGRATION TEST - synthetic data, delete after check"}
        record = call("/health/sleep-record", "POST", payload, token=token, expected=201)
        record_id = record["id"]
        assert record["user_id"] == me["id"] and record["ais_score"] == 2
        call("/health/sleep-record/" + str(record_id), token=token)
    finally:
        if record_id:
            call("/health/sleep-record/" + str(record_id), "DELETE", token=token)
    call("/auth/logout", "POST", token=token)
    call("/auth/me", token=token, expected=401)
    call("/health/sleep-record", "POST", payload, token=token, expected=401)
    call(query, token=token, expected=401)
    print("Synthetic test accounts retained:", name, legacy_name)
    print("Synthetic step records retained on the test account only; no deletion endpoint exists.")


if __name__ == "__main__":
    main()
