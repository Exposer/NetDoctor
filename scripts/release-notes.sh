#!/bin/bash
# Print the GitHub release notes for a version to stdout.
#
#   scripts/release-notes.sh 1.3.0 [path/to/NetDoctor-1.3.0-macOS-universal.zip]
#
# The body is the English CHANGELOG section of that version, preceded by a download / install block
# (with the zip's SHA-256 when the zip is given) and followed by links to both changelogs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=${1:?usage: release-notes.sh <version> [zip]}
ZIP=${2:-}
TAG="v$VER"

python3 - "$ROOT/CHANGELOG.en.md" "$VER" "$TAG" "$ZIP" <<'PY'
import hashlib, os, re, sys
path, ver, tag, zip_path = sys.argv[1:5]
text = open(path, encoding="utf-8").read()
m = re.search(r"^## \[%s\][^\n]*\n(.*?)(?=^## \[|\Z)" % re.escape(ver), text, re.S | re.M)
if not m or not m.group(1).strip():
    sys.exit("no (or empty) '## [%s]' section in CHANGELOG.en.md" % ver)
body = m.group(1).strip()

out = ["## Download / 下载", ""]
if zip_path:
    name = os.path.basename(zip_path)
    sha = hashlib.sha256(open(zip_path, "rb").read()).hexdigest()
    out += ["**`%s`** — native SwiftUI app, macOS 13+, English / 简体中文 (follows the system language)." % name, ""]
    out += ["1. Unzip and drag `NetDoctor.app` to `/Applications`.",
            "2. The app is ad-hoc signed, not notarized, so on first launch macOS may refuse to open it: "
            "**right-click → Open**, or run `xattr -dr com.apple.quarantine /Applications/NetDoctor.app`.",
            "3. 解压后拖进“应用程序”。App 没有经过 Apple 公证,首次打开请**右键 → 打开**,或执行上面的 `xattr` 命令。",
            "", "SHA-256: `%s`" % sha]
else:
    out += ["Build the app yourself with `NetDoctorApp/build-app.sh` (see the README), or use the command line tool `netdoctor`."]
out += ["", "---", "", body, "", "---",
        "中文更新日志 / Chinese: [CHANGELOG.md](https://github.com/Exposer/NetDoctor/blob/%s/CHANGELOG.md) · "
        "Full changelog: [CHANGELOG.en.md](https://github.com/Exposer/NetDoctor/blob/%s/CHANGELOG.en.md)" % (tag, tag)]
print("\n".join(out))
PY
