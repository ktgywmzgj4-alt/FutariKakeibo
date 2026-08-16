#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$project_root" <<'PY'
import json
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
required = [
    root / "project.yml",
    root / "FutariKakeibo" / "App" / "FutariKakeiboApp.swift",
    root / "FutariKakeibo" / "Resources" / "Info.plist",
    root / "FutariKakeibo" / "Resources" / "PrivacyInfo.xcprivacy",
    root / "FutariKakeibo" / "Resources" / "FutariKakeibo.entitlements",
    root / "FutariKakeibo" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png",
]
missing = [str(path.relative_to(root)) for path in required if not path.exists()]
if missing:
    raise SystemExit("missing required files: " + ", ".join(missing))

for path in root.rglob("*.plist"):
    with path.open("rb") as handle:
        plistlib.load(handle)
for path in root.rglob("*.xcprivacy"):
    with path.open("rb") as handle:
        plistlib.load(handle)
for path in root.rglob("Contents.json"):
    with path.open(encoding="utf-8") as handle:
        json.load(handle)

swift_files = list(root.rglob("*.swift"))
if len(swift_files) < 15:
    raise SystemExit(f"unexpectedly few Swift files: {len(swift_files)}")

for path in swift_files:
    text = path.read_text(encoding="utf-8")
    if "http://" in text or "https://" in text:
        raise SystemExit(f"unexpected network URL in {path.relative_to(root)}")

print(f"project structure: OK ({len(swift_files)} Swift files)")
PY

if rg -n --hidden -g '!*.png' -g '!validate_project.sh' \
  '(BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|sk_live_[A-Za-z0-9]+|AKIA[0-9A-Z]{16})' "$project_root"; then
  echo "possible secret detected" >&2
  exit 1
fi

python3 "$project_root/scripts/test_domain_logic.py"
echo "static privacy and secret checks: OK"
