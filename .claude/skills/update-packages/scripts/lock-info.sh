#!/usr/bin/env bash
# Prints the date and revision of the flake's locked nixpkgs next to the host
# system's version, and compares the glibc that the lock would put inside an
# FHS or AppImage sandbox with the glibc the host's GPU drivers were built
# against. A mismatch in the last two lines means every graphical package here
# will fail at startup with GLX or EGL errors until the lock is updated.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import datetime, json
node = json.load(open("flake.lock"))["nodes"]["nixpkgs"]["locked"]
when = datetime.datetime.fromtimestamp(node["lastModified"], datetime.timezone.utc).date()
print(f"locked nixpkgs: {node['rev'][:12]} ({when})")
PY

if command -v nixos-version >/dev/null; then
  echo "host system:    $(nixos-version)"
fi

if [ -e /run/opengl-driver ]; then
  system=$(nix eval --impure --raw --expr 'builtins.currentSystem')
  lock_glibc=$(nix eval --impure --raw --expr "(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${system}.glibc.version")
  host_glibc=$(nix-store -qR /run/opengl-driver | grep -oE 'glibc-[0-9.]+' | sort -uV | tail -1 | sed 's/glibc-//')
  echo "lock glibc:     $lock_glibc"
  echo "host glibc:     $host_glibc (from /run/opengl-driver)"
  if [ "$lock_glibc" != "$host_glibc" ]; then
    echo "WARNING: glibc differs; FHS and AppImage packages will likely fail to start until 'nix flake update nixpkgs' is run."
  fi
fi
