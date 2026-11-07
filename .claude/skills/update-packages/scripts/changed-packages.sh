#!/usr/bin/env bash
# Lists the packages under pkgs/ whose derivation changed, along with the old
# and new version strings, one package per line as tab-separated fields:
#
#   <dir>	<old version>	<new version>
#
# By default it compares the working tree against HEAD, which is what you
# want right after running update-all. Pass a git revision range (for
# example "HEAD~3..HEAD") to inspect commits instead.
#
# The version is taken from the first "version = \"...\"" assignment that
# changed in pkgs/<dir>/default.nix. Packages that derive their version from
# other fields (godot-dev builds it from baseVersion and preLabel) fall back to
# the first changed assignment of any name so that something useful is shown;
# confirm those by reading the diff.
set -euo pipefail

range="${1:-}"

cd "$(git rev-parse --show-toplevel)"

if [ -n "$range" ]; then
  files=$(git diff --name-only "$range" -- pkgs/ | grep '/default.nix$' || true)
else
  files=$(git diff --name-only HEAD -- pkgs/ | grep '/default.nix$' || true)
fi

for f in $files; do
  dir=$(basename "$(dirname "$f")")

  if [ -n "$range" ]; then
    diff=$(git diff -U0 "$range" -- "$f")
  else
    diff=$(git diff -U0 HEAD -- "$f")
  fi

  old=$(printf '%s\n' "$diff" | grep -E '^-\s*version = "' | head -1 | sed -E 's/.*version = "([^"]*)".*/\1/' || true)
  new=$(printf '%s\n' "$diff" | grep -E '^\+\s*version = "' | head -1 | sed -E 's/.*version = "([^"]*)".*/\1/' || true)

  if [ -z "$old" ] || [ -z "$new" ]; then
    old=$(printf '%s\n' "$diff" | grep -E '^-\s*[A-Za-z]+ = "' | head -1 | sed -E 's/^-\s*//' || true)
    new=$(printf '%s\n' "$diff" | grep -E '^\+\s*[A-Za-z]+ = "' | head -1 | sed -E 's/^\+\s*//' || true)
  fi

  printf '%s\t%s\t%s\n' "$dir" "${old:-?}" "${new:-?}"
done
