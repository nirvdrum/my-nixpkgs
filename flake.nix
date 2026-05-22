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
        deadbranch = pkgs.callPackage ./pkgs/deadbranch { };
        freecad-weekly = pkgs.callPackage ./pkgs/freecad-weekly { };
        godot-dev = pkgs.callPackage ./pkgs/godot-dev { };
        godot-dev-mono = pkgs.callPackage ./pkgs/godot-dev { withMono = true; };
        msty-studio = pkgs.callPackage ./pkgs/msty-studio { };
        orion-browser = pkgs.callPackage ./pkgs/orion-browser { };
        textgen = pkgs.callPackage ./pkgs/textgen { };
        whispering = pkgs.callPackage ./pkgs/whispering { };
      }
      // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        claude-desktop = pkgs.callPackage ./pkgs/claude-desktop { };
        textgen-vulkan = pkgs.callPackage ./pkgs/textgen { variant = "vulkan"; };
        textgen-rocm = pkgs.callPackage ./pkgs/textgen { variant = "rocm"; };
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

        # Queries the godot-builds GitHub releases for the newest pre-release
        # snapshot in the next Godot development cycle (dev, beta, or rc tags
        # for the version after the current stable line).  Fetches fresh hashes
        # for both the standard and mono Linux x86_64 archives and rewrites the
        # derivation.  Must be run from the root of the flake checkout.
        updateGodotDevScript = pkgs.writeText "update-godot-dev.py" ''
          import json
          import re
          import subprocess
          import sys
          import os
          import urllib.request

          DERIVATION = "pkgs/godot-dev/default.nix"

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          with open(DERIVATION) as f:
              content = f.read()

          base_match = re.search(r'baseVersion = "([^"]+)"', content)
          pre_match = re.search(r'preLabel = "([^"]+)"', content)
          if not base_match or not pre_match:
              print("error: could not find baseVersion/preLabel in derivation", file=sys.stderr)
              sys.exit(1)

          current_base = base_match.group(1)
          current_pre = pre_match.group(1)
          current_tag = f"{current_base}-{current_pre}"
          print(f"Current: {current_tag}")

          # Fetch recent releases from the godot-builds repository.
          print("Fetching godot-builds release list...")
          tag_pattern = re.compile(r"^(\d+\.\d+)-(dev|beta|rc)(\d+)$")
          page = 1
          candidates = []

          while page <= 5:
              url = f"https://api.github.com/repos/godotengine/godot-builds/releases?per_page=50&page={page}"
              request = urllib.request.Request(
                  url,
                  headers={"Accept": "application/vnd.github+json", "User-Agent": "nix-update-godot-dev"},
              )
              with urllib.request.urlopen(request) as response:
                  releases = json.load(response)

              if not releases:
                  break

              for release in releases:
                  tag = release.get("tag_name", "")
                  m = tag_pattern.match(tag)
                  if m and m.group(1) == current_base:
                      candidates.append(tag)

              page += 1

          if not candidates:
              print(f"error: no pre-release tags found for {current_base}", file=sys.stderr)
              sys.exit(1)

          # Sort candidates so that rc > beta > dev, and higher numbers come first.
          phase_order = {"rc": 2, "beta": 1, "dev": 0}

          def sort_key(tag):
              m = tag_pattern.match(tag)
              return (phase_order.get(m.group(2), -1), int(m.group(3)))

          candidates.sort(key=sort_key, reverse=True)
          latest_tag = candidates[0]
          print(f"Latest:  {latest_tag}")

          if current_tag == latest_tag:
              print("Already up to date.")
              sys.exit(0)

          m = tag_pattern.match(latest_tag)
          new_base = m.group(1)
          new_pre = f"{m.group(2)}{m.group(3)}"

          def prefetch_hash(url):
              result = subprocess.run(
                  ["nix", "store", "prefetch-file", url],
                  capture_output=True, text=True
              )
              h = re.search(r"hash '([^']+)'", result.stdout + result.stderr)
              if not h:
                  print(f"error: could not fetch hash for {url}", file=sys.stderr)
                  sys.exit(1)
              return h.group(1)

          print("Fetching standard Linux x86_64 hash...")
          linux_std_hash = prefetch_hash(
              f"https://github.com/godotengine/godot-builds/releases/download/{latest_tag}/Godot_v{latest_tag}_linux.x86_64.zip"
          )

          print("Fetching mono Linux x86_64 hash...")
          linux_mono_hash = prefetch_hash(
              f"https://github.com/godotengine/godot-builds/releases/download/{latest_tag}/Godot_v{latest_tag}_mono_linux_x86_64.zip"
          )

          print("Fetching standard macOS universal hash...")
          macos_std_hash = prefetch_hash(
              f"https://github.com/godotengine/godot-builds/releases/download/{latest_tag}/Godot_v{latest_tag}_macos.universal.zip"
          )

          print("Fetching mono macOS universal hash...")
          macos_mono_hash = prefetch_hash(
              f"https://github.com/godotengine/godot-builds/releases/download/{latest_tag}/Godot_v{latest_tag}_mono_macos.universal.zip"
          )

          content = content.replace(
              f'baseVersion = "{current_base}"',
              f'baseVersion = "{new_base}"',
          )
          content = content.replace(
              f'preLabel = "{current_pre}"',
              f'preLabel = "{new_pre}"',
          )
          content = re.sub(
              r'(linux\.x86_64\.zip";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + linux_std_hash + m.group(2),
              content,
          )
          content = re.sub(
              r'(mono_linux_x86_64\.zip";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + linux_mono_hash + m.group(2),
              content,
          )
          content = re.sub(
              r'(_macos\.universal\.zip";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + macos_std_hash + m.group(2),
              content,
          )
          content = re.sub(
              r'(_mono_macos\.universal\.zip";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + macos_mono_hash + m.group(2),
              content,
          )

          with open(DERIVATION, "w") as f:
              f.write(content)

          print(f"Updated {DERIVATION} from {current_tag} to {latest_tag}.")
          print("Stage the change with: git add pkgs/godot-dev/default.nix")
        '';

        # Queries the claude-desktop-debian GitHub releases for the newest
        # release tag (format: v<wrapper>+claude<app>), fetches the fresh hash
        # for the x86_64 AppImage, and rewrites the derivation.  Must be run
        # from the root of the flake checkout.
        updateClaudeDesktopScript = pkgs.writeText "update-claude-desktop.py" ''
          import json
          import re
          import subprocess
          import sys
          import os
          import urllib.request

          DERIVATION = "pkgs/claude-desktop/default.nix"
          REPO_RELEASES_API = "https://api.github.com/repos/aaddrick/claude-desktop-debian/releases?per_page=10"
          TAG_PATTERN = re.compile(r"^v(\d+\.\d+\.\d+)\+claude(\d+\.\d+\.\d+)$")

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          print("Fetching claude-desktop-debian release list...")
          request = urllib.request.Request(
              REPO_RELEASES_API,
              headers={"Accept": "application/vnd.github+json", "User-Agent": "nix-update-claude-desktop"},
          )

          with urllib.request.urlopen(request) as response:
              releases = json.load(response)

          latest_wrapper = None
          latest_claude = None
          for release in releases:
              tag = release.get("tag_name", "")
              m = TAG_PATTERN.match(tag)
              if m:
                  latest_wrapper = m.group(1)
                  latest_claude = m.group(2)
                  break

          if not latest_wrapper or not latest_claude:
              print("error: could not determine latest release tag", file=sys.stderr)
              sys.exit(1)

          with open(DERIVATION) as f:
              content = f.read()

          current_version = re.search(r'version = "([^"]+)"', content)
          current_wrapper = re.search(r'wrapperVersion = "([^"]+)"', content)
          if not current_version or not current_wrapper:
              print("error: could not find current versions in derivation", file=sys.stderr)
              sys.exit(1)

          current_v = current_version.group(1)
          current_w = current_wrapper.group(1)
          print(f"Current: {current_v} (wrapper {current_w})")
          print(f"Latest:  {latest_claude} (wrapper {latest_wrapper})")

          if current_v == latest_claude and current_w == latest_wrapper:
              print("Already up to date.")
              sys.exit(0)

          url = f"https://github.com/aaddrick/claude-desktop-debian/releases/download/v{latest_wrapper}%2Bclaude{latest_claude}/claude-desktop-{latest_claude}-{latest_wrapper}-amd64.AppImage"

          print("Fetching x86_64 AppImage hash...")
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

          content = content.replace(f'version = "{current_v}"', f'version = "{latest_claude}"', 1)
          content = content.replace(f'wrapperVersion = "{current_w}"', f'wrapperVersion = "{latest_wrapper}"', 1)
          content = re.sub(
              r'(amd64\.AppImage";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + new_hash + m.group(2),
              content,
          )

          with open(DERIVATION, "w") as f:
              f.write(content)

          print(f"Updated {DERIVATION}: {current_v} -> {latest_claude} (wrapper {current_w} -> {latest_wrapper}).")
          print("Stage the change with: git add pkgs/claude-desktop/default.nix")
        '';

        # Queries the EpicenterHQ/epicenter GitHub releases for the newest
        # Whispering release tag (format: v<X.Y.Z>) and rewrites the
        # derivation with fresh hashes for the Linux x86_64 AppImage and the
        # macOS aarch64 .app tarball.  The monorepo also publishes non-
        # Whispering tags such as `_assets` and `models/<name>`; we filter
        # those out by both the tag regex and by verifying that the chosen
        # release ships a Whispering AppImage asset.  Must be run from the
        # root of the flake checkout.
        updateWhisperingScript = pkgs.writeText "update-whispering.py" ''
          import json
          import re
          import subprocess
          import sys
          import os
          import urllib.request

          DERIVATION = "pkgs/whispering/default.nix"
          REPO_RELEASES_API = "https://api.github.com/repos/EpicenterHQ/epicenter/releases?per_page=30"
          TAG_PATTERN = re.compile(r"^v(\d+\.\d+\.\d+)$")

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          print("Fetching EpicenterHQ/epicenter release list...")
          request = urllib.request.Request(
              REPO_RELEASES_API,
              headers={"Accept": "application/vnd.github+json", "User-Agent": "nix-update-whispering"},
          )

          with urllib.request.urlopen(request) as response:
              releases = json.load(response)

          # Iterate in API order (newest first) until we find a tag that both
          # matches our version pattern and ships a Whispering asset.  This
          # protects against future tags in the monorepo that share the v*
          # prefix but are not Whispering releases.
          latest = None
          for release in releases:
              tag = release.get("tag_name", "")
              m = TAG_PATTERN.match(tag)
              if not m:
                  continue
              asset_names = [asset.get("name", "") for asset in release.get("assets", [])]
              if any(name.startswith("Whispering_") and name.endswith(".AppImage") for name in asset_names):
                  latest = m.group(1)
                  break

          if not latest:
              print("error: could not determine latest Whispering release tag", file=sys.stderr)
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

          def prefetch_hash(url):
              result = subprocess.run(
                  ["nix", "store", "prefetch-file", url],
                  capture_output=True, text=True
              )
              h = re.search(r"hash '([^']+)'", result.stdout + result.stderr)
              if not h:
                  print(f"error: could not fetch hash for {url}", file=sys.stderr)
                  sys.exit(1)
              return h.group(1)

          print("Fetching Linux x86_64 AppImage hash...")
          linux_hash = prefetch_hash(
              f"https://github.com/EpicenterHQ/epicenter/releases/download/v{latest}/Whispering_{latest}_amd64.AppImage"
          )

          print("Fetching macOS aarch64 .app tarball hash...")
          macos_hash = prefetch_hash(
              f"https://github.com/EpicenterHQ/epicenter/releases/download/v{latest}/Whispering_aarch64.app.tar.gz"
          )

          content = content.replace(f'version = "{current}"', f'version = "{latest}"', 1)
          content = re.sub(
              r'(amd64\.AppImage";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + linux_hash + m.group(2),
              content,
          )
          content = re.sub(
              r'(aarch64\.app\.tar\.gz";\n\s+hash = ")[^"]+(")',
              lambda m: m.group(1) + macos_hash + m.group(2),
              content,
          )

          with open(DERIVATION, "w") as f:
              f.write(content)

          print(f"Updated {DERIVATION} from {current} to {latest}.")
          print("Stage the change with: git add pkgs/whispering/default.nix")
        '';

        # Queries the oobabooga/textgen GitHub releases for the newest
        # release tag (format: v<X.Y.Z>), fetches fresh hashes for all
        # variant assets (cpu, vulkan, rocm on Linux; arm64 on macOS),
        # and rewrites the derivation.  Must be run from the root of
        # the flake checkout.
        updateTextgenScript = pkgs.writeText "update-textgen.py" ''
          import json
          import re
          import subprocess
          import sys
          import os
          import urllib.request

          DERIVATION = "pkgs/textgen/default.nix"
          REPO_RELEASES_API = "https://api.github.com/repos/oobabooga/textgen/releases?per_page=10"
          TAG_PATTERN = re.compile(r"^v(\d+\.\d+)$")

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          print("Fetching textgen release list...")
          request = urllib.request.Request(
              REPO_RELEASES_API,
              headers={"Accept": "application/vnd.github+json", "User-Agent": "nix-update-textgen"},
          )

          with urllib.request.urlopen(request) as response:
              releases = json.load(response)

          latest = None
          for release in releases:
              tag = release.get("tag_name", "")
              m = TAG_PATTERN.match(tag)
              if m:
                  latest = m.group(1)
                  break

          if not latest:
              print("error: could not determine latest release tag", file=sys.stderr)
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

          def prefetch_hash(url):
              result = subprocess.run(
                  ["nix", "store", "prefetch-file", url],
                  capture_output=True, text=True
              )
              h = re.search(r"hash '([^']+)'", result.stdout + result.stderr)
              if not h:
                  print(f"error: could not fetch hash for {url}", file=sys.stderr)
                  sys.exit(1)
              return h.group(1)

          # Linux variants: cpu, vulkan, rocm; macOS: arm64
          variants = ["linux-cpu", "linux-vulkan", "linux-rocm", "macos-arm64"]
          hash_map = {}

          # The ROCm asset has ".2" appended to the variant name
          def asset_suffix(v):
              if v == "linux-rocm":
                  return "linux-rocm7.2"
              return v

          for v in variants:
              suffix = asset_suffix(v)
              url = f"https://github.com/oobabooga/textgen/releases/download/v{latest}/textgen-portable-{latest}-{suffix}.tar.gz"
              print(f"Fetching hash for {v}...")
              hash_map[v] = prefetch_hash(url)

          # Replace version
          content = content.replace(f'version = "{current}"', f'version = "{latest}"', 1)

          # Replace hashes in the hash attribute set
          for v in variants:
              key = v  # the nix attr key, e.g. "linux-cpu", "macos-arm64"
              content = re.sub(
                  rf'("{key}" \= \")[^"]+(")',
                  lambda m: m.group(1) + hash_map[v] + m.group(2),
                  content
              )

          with open(DERIVATION, "w") as f:
              f.write(content)

          print(f"Updated {DERIVATION} from {current} to {latest}.")
          print("Stage the change with: git add pkgs/textgen/default.nix")
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
        update-claude-desktop = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-claude-desktop" ''
            exec ${pkgs.python3}/bin/python3 ${updateClaudeDesktopScript}
          '');
        };

        update-deadbranch = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-deadbranch" ''
            exec ${pkgs.nix-update}/bin/nix-update --flake deadbranch --version-regex 'v(.*)'
          '');
        };

        update-freecad-weekly = {
          type = "app";
          # Filters to weekly-YYYY.MM.DD tags only, so a stable 1.x release
          # landing on the GitHub releases page doesn't get picked up as an update.
          program = toString (pkgs.writeShellScript "update-freecad-weekly" ''
            exec ${pkgs.nix-update}/bin/nix-update --flake freecad-weekly --version-regex 'weekly-(.*)'
          '');
        };

        update-godot-dev = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-godot-dev" ''
            exec ${pkgs.python3}/bin/python3 ${updateGodotDevScript}
          '');
        };

        update-msty-studio = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-msty-studio" ''
            exec ${pkgs.python3}/bin/python3 ${updateMstyStudioScript}
          '');
        };

        update-textgen = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-textgen" ''
            exec ${pkgs.python3}/bin/python3 ${updateTextgenScript}
          '');
        };

        update-vibe = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-vibe" ''
            exec ${pkgs.python3}/bin/python3 ${updateVibeScript}
          '');
        };

        update-whispering = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-whispering" ''
            exec ${pkgs.python3}/bin/python3 ${updateWhisperingScript}
          '');
        };

        update-all = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-all" ''
            failed=""

            for app in update-claude-desktop update-deadbranch update-freecad-weekly update-godot-dev update-msty-studio update-textgen update-vibe update-whispering; do
              echo "=== Running $app ==="
              if nix run .#"$app"; then
                echo "=== $app completed successfully ==="
              else
                echo "=== $app failed ==="
                failed="$failed $app"
              fi
              echo ""
            done

            if [ -n "$failed" ]; then
              echo "The following updaters failed:$failed"
              exit 1
            else
              echo "All updaters completed successfully."
            fi
          '');
        };
      });
  };
}
