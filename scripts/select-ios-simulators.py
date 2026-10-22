#!/usr/bin/env python3
"""Select available simulators supported by the active Xcode SDK."""
import json
import os
import re
import subprocess

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
sdk_text = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
sdk = tuple(int(part) for part in sdk_text.split(".")[:2])
compatible = []
for runtime, entries in devices.items():
    match = re.search(r"\.iOS-(\d+)-(\d+)", runtime)
    if match:
        version = tuple(map(int, match.groups()))
        if version <= sdk and entries:
            compatible.append((version, entries))
if not compatible:
    raise SystemExit("No iOS simulator compatible with the selected Xcode SDK")
version, available = max(compatible, key=lambda item: item[0])
selected = {}
for label, prefix in [("PHONE", "iPhone"), ("TABLET", "iPad")]:
    device = next(entry for entry in available if entry["name"].startswith(prefix))
    selected[label + "_UDID"] = device["udid"]
    print(label, device["name"])
print("SDK", sdk_text, "simulator runtime", version)
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"], "a") as output:
        for key, value in selected.items():
            output.write(key + "=" + value + "\n")
else:
    print(json.dumps(selected))
