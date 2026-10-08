#!/usr/bin/env bash
# Full headless check: import, run tests, then run the main scene for 5 seconds.
# Fails on test failures and on any script/parse error in the output.
#   tools/check.sh            (GODOT=/path/to/godot to override the binary)
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
status=0

echo "== import"
"$GODOT" --headless --path . --import >"$log" 2>&1 || status=1

echo "== tests"
"$GODOT" --headless --path . -s res://tests/test_runner.gd 2>&1 | tee -a "$log" | grep -vE '^(Godot Engine|$)'
[ "${PIPESTATUS[0]}" -eq 0 ] || status=1

echo "== run main scene (300 frames)"
"$GODOT" --headless --path . --quit-after 300 >>"$log" 2>&1 || status=1

if grep -nE 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$log"; then
	echo "!! errors found in Godot output (above)"
	status=1
fi
if grep -nE 'WARNING:' "$log" | grep -vE 'wd.xic|DRI_PRIME' ; then
	echo "(warnings above)"
fi
[ $status -eq 0 ] && echo "== all checks passed" || echo "== CHECK FAILED"
exit $status
