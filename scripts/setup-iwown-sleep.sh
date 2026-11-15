#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="${1:?Usage: bash scripts/setup-iwown-sleep.sh /path/to/manufacturer/Sleep}"
verify() {
    actual=$(shasum -a 256 "$source_dir/$1" | awk '{print $1}')
    if [[ "$actual" != "$2" ]]; then
        echo "error: Unexpected $1 version. Review the new SDK before changing its checksum." >&2
        exit 1
    fi
}
verify IVSleep.a 9c932284b3a6d269b5861d788bd212bad203206751ab8d7a934d546753c933ea
verify IVSleep.h fe028407dd8785c10c70007334bd4067348dae2b5affd884bfda1f70a2a656c7
mkdir -p "$root/Vendor/IwownSleep"
cp "$source_dir/IVSleep.a" "$source_dir/IVSleep.h" "$root/Vendor/IwownSleep/"
echo "Verified and installed the manufacturer sleep SDK locally."
