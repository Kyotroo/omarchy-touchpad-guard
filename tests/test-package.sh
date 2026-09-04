#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$ROOT"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

jq -e '
  .schemaVersion == 1
  and .id == "kdm.touchpad-guard"
  and .name == "Touchpad Guard"
  and .version == "1.0.0"
  and .author == "Kyotroo"
  and .license == "MIT"
  and .homepage == "https://github.com/Kyotroo/omarchy-touchpad-guard"
  and (.kinds | index("bar-widget") != null)
  and .entryPoints.barWidget == "TouchpadGuard.qml"
  and .barWidget.allowMultiple == false
  and .barWidget.category == "System"
  and .barWidget.defaultSection == "right"
' manifest.json >/dev/null

entry_point=$(jq -r '.entryPoints.barWidget' manifest.json)
[[ $entry_point != /* && $entry_point != *..* ]]
[[ -r $entry_point ]]
[[ -x bin/touchpad-guard ]]
[[ -s README.md ]] || { echo "README.md is missing or empty" >&2; exit 1; }
[[ -s LICENSE ]] || { echo "LICENSE is missing or empty" >&2; exit 1; }
[[ -s docs/testing/2026-09-05-release-evidence.md ]] || {
  echo "release evidence is missing or empty" >&2
  exit 1
}
grep -F 'MIT License' LICENSE >/dev/null
grep -F '![Touchpad Guard panel](preview.png)' README.md >/dev/null
[[ -s preview.png ]] || { echo "preview.png is missing or empty" >&2; exit 1; }
dimensions=$(magick identify -format '%wx%h' preview.png 2>/dev/null)
[[ $dimensions == 1440x900 ]] || {
  echo "preview.png must be 1440x900, got $dimensions" >&2
  exit 1
}
node <<'NODE'
const fs = require("node:fs")
const image = fs.readFileSync("preview.png")
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])
if (!image.subarray(0, 8).equals(signature)) throw new Error("preview is not PNG")
if (image.readUInt32BE(16) !== 1440 || image.readUInt32BE(20) !== 900)
  throw new Error("preview PNG header has wrong dimensions")
const forbidden = new Set(["tEXt", "zTXt", "iTXt", "eXIf"])
for (let offset = 8; offset + 12 <= image.length;) {
  const length = image.readUInt32BE(offset)
  const type = image.toString("ascii", offset + 4, offset + 8)
  if (forbidden.has(type)) throw new Error(`preview contains ${type} metadata`)
  offset += 12 + length
}
NODE

if ! grep -A3 'name.indexOf("deviceadded")' TouchpadGuard.qml \
    | grep -F 'reapplyTimer.restart()' >/dev/null; then
  echo "device changes must silently reapply the active mode" >&2
  exit 1
fi

if ! grep -A4 'interval: 7500' TouchpadGuard.qml \
    | grep -F 'onTriggered: root.reapply()' >/dev/null; then
  echo "the health timer must silently reconcile the active mode" >&2
  exit 1
fi

export PATH="$ROOT/tests/fixtures/bin:/usr/bin:/bin"
export TOUCHPAD_GUARD_STATE_DIR="$tmp/state"
export TOUCHPAD_GUARD_TOGGLE_MARKER="$tmp/touchpad-disabled-name"
export HYPRLAND_INSTANCE_SIGNATURE="package-test"
export FAKE_HYPR_LOG="$tmp/hypr.log"
export FAKE_TOGGLE_LOG="$tmp/toggle.log"
export FAKE_OSD_LOG="$tmp/osd.log"
: >"$FAKE_HYPR_LOG"
: >"$FAKE_TOGGLE_LOG"
: >"$FAKE_OSD_LOG"

status=$(bin/touchpad-guard status)
jq -e '.ok == true and .devices == ["test-touchpad"]' <<<"$status" >/dev/null

if git grep -E 'bash[[:space:]]+-c' -- '*.qml' bin/ 2>/dev/null; then
  echo "shell-string execution is not allowed" >&2
  exit 1
fi

for source in TouchpadGuard.qml Panel.qml Model.js bin/touchpad-guard; do
  [[ -e $source ]] || continue
  if grep -F "$HOME" "$source" >/dev/null; then
    echo "private home path found in $source" >&2
    exit 1
  fi
done

if git grep -I -F "$HOME" -- ':!tests/test-package.sh' >/dev/null 2>&1; then
  echo "private home path found in tracked content" >&2
  exit 1
fi

if git grep -I -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -- ':!LICENSE' >/dev/null 2>&1; then
  echo "email address found in tracked content" >&2
  exit 1
fi

if find . -path './.git' -prune -o -path './.worktrees' -prune -o -type l -print -quit | grep -q .; then
  echo "repository must not contain symlinks" >&2
  exit 1
fi

printf 'package contract ok\n'
