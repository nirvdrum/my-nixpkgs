{
  description = "Personal Nix packages";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  in
  {
    packages = forAllSystems (system:
      let pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      in {
        freecad-weekly = pkgs.callPackage ./pkgs/freecad-weekly { };
        msty-studio = pkgs.callPackage ./pkgs/msty-studio { };
      }
      // nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
        vibe = pkgs.callPackage ./pkgs/vibe { };
      }
      // {
        default = self.packages.${system}.freecad-weekly;
      });

    apps = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Queries the Msty changelog for the latest version, fetches fresh hashes
        # for both the Linux AppImage and macOS DMG, and rewrites the derivation.
        # Must be run from the root of the flake checkout.
        updateMstyStudioScript = pkgs.writeText "update-msty-studio.py" ''
          import re
          import subprocess
          import sys
          import os
          import urllib.request

          DERIVATION = "pkgs/msty-studio/default.nix"

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          print("Fetching Msty changelog...")
          req = urllib.request.Request(
              "https://msty.ai/changelog",
              headers={"User-Agent": "nix-update-msty-studio/1.0"},
          )
          with urllib.request.urlopen(req) as response:
              html = response.read().decode()

          # The changelog uses anchor IDs of the form id="msty-X.Y.Z" on each
          # release heading; the first match is the most recent release.
          match = re.search(r'id="msty-(\d+\.\d+\.\d+)"', html)
          if not match:
              print("error: could not determine latest version from changelog", file=sys.stderr)
              sys.exit(1)

          latest = match.group(1)

          with open(DERIVATION) as f:
              content = f.read()

          current_match = re.search(r'version = "([^"]+)"', content)
          if not current_match:
              print("error: could not find current version in derivation", file=sys.stderr)
              sys.exit(1)

          current = current_match.group(1)
          print(f"Current: {current}  Latest: {latest}")

          if current == latest:
              print("Already up to date.")
              sys.exit(0)

          def prefetch_hash(url):
              result = subprocess.run(
                  ["nix", "store", "prefetch-file", url],
                  capture_output=True, text=True
              )
              m = re.search(r"hash '([^']+)'", result.stdout + result.stderr)
              if not m:
                  print(f"error: could not fetch hash for {url}", file=sys.stderr)
                  sys.exit(1)
              return m.group(1)

          print("Fetching Linux AppImage hash...")
          linux_hash = prefetch_hash(
              "https://next-assets.msty.studio/app/latest/linux/MstyStudio_x86_64.AppImage"
          )

          print("Fetching macOS DMG hash...")
          macos_hash = prefetch_hash(
              f"https://next-assets.msty.studio/app/latest/mac/MstyStudio_arm64.dmg?ver={latest}"
          )

          content = content.replace(f'version = "{current}"', f'version = "{latest}"', 1)
          content = re.sub(
              r'(AppImage";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + linux_hash + m.group(2),
              content
          )
          content = re.sub(
              r'(arm64\.dmg[^"]*";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + macos_hash + m.group(2),
              content
          )

          with open(DERIVATION, "w") as f:
              f.write(content)

          print(f"Updated {DERIVATION} from {current} to {latest}.")
          print("Stage the change with: git add pkgs/msty-studio/default.nix")
        '';

        # Finds the newest date+SHA release tag (excluding the rolling "latest"
        # tag), fetches a fresh hash for the macOS ARM64 zip, and rewrites the
        # derivation. Must be run from the root of the flake checkout.
        updateVibeScript = pkgs.writeText "update-vibe.py" ''
          import json
          import re
          import subprocess
          import sys
          import os
          import urllib.request

          DERIVATION = "pkgs/vibe/default.nix"
          REPO_RELEASES_API = "https://api.github.com/repos/lynaghk/vibe/releases?per_page=20"
          TAG_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}-[0-9a-f]{7}$")

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          print("Fetching Vibe release list...")
          request = urllib.request.Request(
              REPO_RELEASES_API,
              headers={"Accept": "application/vnd.github+json", "User-Agent": "nix-update-vibe-script"},
          )

          with urllib.request.urlopen(request) as response:
              releases = json.load(response)

          latest = None
          for release in releases:
              tag = release.get("tag_name", "")
              if TAG_PATTERN.match(tag):
                  latest = tag
                  break

          if not latest:
              print("error: could not determine latest date+SHA release tag", file=sys.stderr)
              sys.exit(1)

          with open(DERIVATION) as f:
              content = f.read()

          current_match = re.search(r'version = "([^"]+)"', content)
          if not current_match:
              print("error: could not find current version in derivation", file=sys.stderr)
              sys.exit(1)

          current = current_match.group(1)
          print(f"Current: {current}  Latest: {latest}")

          if current == latest:
              print("Already up to date.")
              sys.exit(0)

          url = f"https://github.com/lynaghk/vibe/releases/download/{latest}/vibe-macos-arm64.zip"

          print("Fetching macOS ARM64 zip hash...")
          result = subprocess.run(
              ["nix", "store", "prefetch-file", url],
              capture_output=True,
              text=True,
          )
          hash_match = re.search(r"hash '([^']+)'", result.stdout + result.stderr)
          if not hash_match:
              print(f"error: could not fetch hash for {url}", file=sys.stderr)
              sys.exit(1)

          new_hash = hash_match.group(1)

          content = content.replace(f'version = "{current}"', f'version = "{latest}"', 1)
          content = re.sub(
              r'(vibe-macos-arm64\.zip";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + new_hash + m.group(2),
              content,
          )

          with open(DERIVATION, "w") as f:
              f.write(content)

          print(f"Updated {DERIVATION} from {current} to {latest}.")
          print("Stage the change with: git add pkgs/vibe/default.nix")
        '';
      in
      {
        update-freecad-weekly = {
          type = "app";
          # Filters to weekly-YYYY.MM.DD tags only, so a stable 1.x release
          # landing on the GitHub releases page doesn't get picked up as an update.
          program = toString (pkgs.writeShellScript "update-freecad-weekly" ''
            exec ${pkgs.nix-update}/bin/nix-update --flake freecad-weekly --version-regex 'weekly-.*'
          '');
        };

        update-msty-studio = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-msty-studio" ''
            exec ${pkgs.python3}/bin/python3 ${updateMstyStudioScript}
          '');
        };

        update-vibe = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-vibe" ''
            exec ${pkgs.python3}/bin/python3 ${updateVibeScript}
          '');
        };
      });
  };
}
