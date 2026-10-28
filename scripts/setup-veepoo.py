#!/usr/bin/env python3
"""Fetch the pinned vendor distribution; verify each Git blob before using it."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / "Configuration/VeepooManifest.json").read_text())
DESTINATION = ROOT / "Vendor/Veepoo"


def blob_id(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def fetch(entry):
    target = DESTINATION / entry["destination"]
    if target.exists() and blob_id(target.read_bytes()) == entry["sha"]:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    source = quote(entry["source"], safe="/")
    revision = MANIFEST["revision"]
    urls = [
        f"https://cdn.jsdelivr.net/gh/HBandSDK/iOS_Ble_SDK@master/{source}",
        f"https://cdn.jsdelivr.net/gh/HBandSDK/iOS_Ble_SDK@{revision}/{source}",
        f"https://raw.githubusercontent.com/HBandSDK/iOS_Ble_SDK/{revision}/{source}",
    ]
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as handle:
        temporary = Path(handle.name)
    try:
        for url in urls:
            result = subprocess.run([
                "curl", "--fail", "--location", "--silent", "--show-error",
                "--connect-timeout", "8", "--max-time", "45",
                "--output", str(temporary), url,
            ], capture_output=True)
            if result.returncode == 0 and blob_id(temporary.read_bytes()) == entry["sha"]:
                temporary.replace(target)
                return
        raise RuntimeError(f"Download or checksum failed: {entry['destination']}")
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(fetch, entry) for entry in MANIFEST["files"]]
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                future.result()
            except Exception as error:
                failures.append(str(error))
            if index % 50 == 0:
                print(f"Checked {index}/{len(futures)}", flush=True)
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"Verified {len(MANIFEST['files'])} vendor files in {DESTINATION}")
