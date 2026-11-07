#!/usr/bin/env bash
# Launches a graphical package long enough to prove it gets past startup,
# then shuts it down. Prints PASS or FAIL and the reason, and exits non-zero on
# failure.
#
#   smoke-gui.sh <flake attr> [seconds to wait, default 20]
#
# A GUI app that dies during startup usually does so within a few seconds,
# and the fatal message lands on stderr (missing shared libraries, glibc
# symbol versions, GLX or EGL initialization, Electron sandbox errors).
# A process that is still alive after the wait and printed none of those
# is considered healthy. The log is kept so you can read it on failure.
#
# AppImage and FHS wrappers run the real program under bubblewrap in a new
# process group, so killing the wrapper alone leaves the app on screen.
# The script therefore kills the whole session it started.
#
# Logs go to $SMOKE_LOG_DIR when set, otherwise to the usual temp directory.
set -uo pipefail

attr="${1:?usage: smoke-gui.sh <flake attr> [seconds]}"
wait_seconds="${2:-20}"
log=$(mktemp -p "${SMOKE_LOG_DIR:-${TMPDIR:-/tmp}}" smoke-gui-XXXXXX.log)

# setsid gives the app its own session so that everything it spawns can be
# killed together by session id, including bubblewrap children.
setsid nix run ".#$attr" >"$log" 2>&1 &
sid=$!

sleep "$wait_seconds"

fatal='error while loading shared libraries|GLIBC_[0-9.]+. not found|symbol lookup error|Could not initialize GLX|Could not create default EGL display|EGL_BAD|Segmentation fault|core dumped|Aborted|FATAL|Trace/breakpoint trap|SUID sandbox helper|cannot execute'

if ! kill -0 "$sid" 2>/dev/null; then
  echo "FAIL: $attr exited within ${wait_seconds}s"
  echo "--- last 30 lines of $log ---"
  tail -30 "$log"
  exit 1
fi

if grep -Eq "$fatal" "$log"; then
  echo "FAIL: $attr is running but logged a fatal-looking message"
  grep -En "$fatal" "$log" | head -10
  echo "--- full log: $log ---"
  pkill -TERM -s "$sid" 2>/dev/null
  exit 1
fi

pkill -TERM -s "$sid" 2>/dev/null
sleep 2
pkill -KILL -s "$sid" 2>/dev/null

echo "PASS: $attr ran for ${wait_seconds}s without fatal output (log: $log)"
# The first lines usually carry the app's own version banner, which is the
# cheapest confirmation that the new version is the one that launched.
echo "--- first 5 lines of output ---"
grep -v "Git tree .* is dirty" "$log" | head -5 || true
exit 0
