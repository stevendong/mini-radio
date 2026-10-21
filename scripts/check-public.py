#!/usr/bin/env python3
"""Conservative public-source checks. Never print matching sensitive values."""
import re
import subprocess
from pathlib import Path

rules = {
    "private document URL": re.compile(r"https://(?:app\.)?notion\.(?:com|so)/(?:p/)?[0-9a-f-]{32,}", re.I),
    "local workspace path": re.compile(r"/(?:data|home)/[A-Za-z0-9_.-]+"),
    "private key material": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "GitHub credential": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b"),
    "provider credential": re.compile(r"\b(?:AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{32,})\b"),
    "personal email": re.compile(r"\b[A-Za-z0-9_.+-]+@(?:gmail\.com|outlook\.com|hotmail\.com|qq\.com|126\.com|163\.com)\b", re.I),
}
files = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
failures = []
for filename in filter(None, files):
    path = Path(filename)
    if path.name == ".env" or path.suffix.lower() in {".pem", ".p12", ".mobileprovision", ".key"}:
        failures.append((filename, "sensitive file type"))
    try:
        content = path.read_text()
    except (UnicodeError, FileNotFoundError):
        continue
    for label, pattern in rules.items():
        if pattern.search(content):
            failures.append((filename, label))
for filename, label in failures:
    print(f"Public-source check failed: {filename}: {label}")
if failures:
    raise SystemExit(1)
print(f"Public-source checks passed for {sum(bool(f) for f in files)} tracked files.")
