{
  description = "Personal Nix packages";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-26.05";
  };

  outputs = { self, nixpkgs, nixpkgs-stable }:
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
        actual-cli = pkgs.callPackage ./pkgs/actual-cli { };
        deadbranch = pkgs.callPackage ./pkgs/deadbranch { };
        fastmail = pkgs.callPackage ./pkgs/fastmail { };
        fastmail-cli = pkgs.callPackage ./pkgs/fastmail-cli { };
        fastmail-rules-cli = pkgs.callPackage ./pkgs/fastmail-rules-cli { };
        freecad-weekly = pkgs.callPackage ./pkgs/freecad-weekly { };
        godot-dev = pkgs.callPackage ./pkgs/godot-dev { };
        godot-dev-mono = pkgs.callPackage ./pkgs/godot-dev { withMono = true; };
        msty-studio = pkgs.callPackage ./pkgs/msty-studio { };
        orion-browser = pkgs.callPackage ./pkgs/orion-browser {
          # The bundled WebKitGTK was compiled against libjxl 0.11
          # (SONAME libjxl.so.0.11), but nixpkgs unstable ships 0.12.
          # Pull the 0.11.x library from the stable branch, which is
          # cached on Hydra and requires no source build.
          libjxl = nixpkgs-stable.legacyPackages.${system}.libjxl;
        };
        textgen = pkgs.callPackage ./pkgs/textgen { };
        whispering = pkgs.callPackage ./pkgs/whispering { };
      }
      // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        textgen-vulkan = pkgs.callPackage ./pkgs/textgen { variant = "vulkan"; };
        textgen-rocm = pkgs.callPackage ./pkgs/textgen { variant = "rocm"; };
      }
      // nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
        ds4 = pkgs.callPackage ./pkgs/ds4 { };
        vibe = pkgs.callPackage ./pkgs/vibe { };
      }
      // {
        default = self.packages.${system}.freecad-weekly;
      });

    apps = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Queries the npm registry for the latest stable @actual-app/cli
        # release, regenerates the vendored production package-lock.json (the
        # published tarball ships none), prefetches the source and npm-deps
        # hashes, and rewrites the derivation. Must be run from the root of
        # the flake checkout.
        updateActualCliScript = pkgs.writeText "update-actual-cli.py" ''
          import json
          import os
          import re
          import subprocess
          import sys
          import tarfile
          import tempfile
          import urllib.request

          if len(sys.argv) != 6:
              print("usage: update-actual-cli.py <derivation> <lockfile> <npm> <prefetch-npm-deps> <nix>", file=sys.stderr)
              sys.exit(1)

          derivation = sys.argv[1]
          lockfile = sys.argv[2]
          npm = sys.argv[3]
          prefetch_npm_deps = sys.argv[4]
          nix = sys.argv[5]

          registry = "https://registry.npmjs.org/@actual-app/cli"

          if not os.path.exists(derivation):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          print("Fetching @actual-app/cli dist-tags...")
          request = urllib.request.Request(
              registry,
              headers={"User-Agent": "nix-update-actual-cli/1.0"},
          )
          with urllib.request.urlopen(request) as response:
              meta = json.load(response)

          latest = meta["dist-tags"]["latest"]

          with open(derivation) as f:
              content = f.read()

          current = re.search(r'version = "([^"]+)"', content).group(1)
          print(f"Current: {current}  Latest: {latest}")

          if current == latest:
              print("Already up to date.")
              sys.exit(0)

          tarball_url = f"https://registry.npmjs.org/@actual-app/cli/-/cli-{latest}.tgz"

          def nix_prefetch_file(url):
              result = subprocess.run(
                  [nix, "store", "prefetch-file", "--json", url],
                  capture_output=True, text=True,
              )
              if result.returncode == 0:
                  data = json.loads(result.stdout)
                  h = data.get("hash")
                  if h:
                      return h
              # Fall back to the human-readable output of older Nix versions.
              result = subprocess.run(
                  [nix, "store", "prefetch-file", url],
                  capture_output=True, text=True,
              )
              m = re.search(r"hash '([^']+)'", result.stdout + result.stderr)
              if not m:
                  print(f"error: could not fetch hash for {url}", file=sys.stderr)
                  print(result.stdout + result.stderr, file=sys.stderr)
                  sys.exit(1)
              return m.group(1)

          print("Prefetching source tarball hash...")
          src_hash = nix_prefetch_file(tarball_url)

          print("Regenerating production package-lock.json...")
          with tempfile.TemporaryDirectory() as tmp:
              tarball_path = os.path.join(tmp, "cli.tgz")
              with urllib.request.urlopen(tarball_url) as response, open(tarball_path, "wb") as out:
                  out.write(response.read())

              with tarfile.open(tarball_path, "r:gz") as tar:
                  tar.extractall(tmp)

              src_dir = os.path.join(tmp, "package")
              subprocess.run(
                  [npm, "install", "--package-lock-only", "--omit=dev", "--no-audit", "--no-fund"],
                  cwd=src_dir, check=True,
                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
              )

              with open(os.path.join(src_dir, "package-lock.json"), "rb") as src, open(lockfile, "wb") as dst:
                  dst.write(src.read())

          print("Prefetching npm deps hash...")
          result = subprocess.run(
              [prefetch_npm_deps, lockfile],
              capture_output=True, text=True,
          )
          npm_deps_hash = result.stdout.strip().splitlines()[-1].strip() if result.stdout.strip() else ""
          if not npm_deps_hash.startswith("sha256-"):
              print("error: could not determine npm deps hash", file=sys.stderr)
              print(result.stdout + result.stderr, file=sys.stderr)
              sys.exit(1)

          content = content.replace(f'version = "{current}"', f'version = "{latest}"', 1)
          content = re.sub(
              r'(cli-\$\{version\}\.tgz";\n\s+hash = ")[^"]+(";)',
              lambda m: m.group(1) + src_hash + m.group(2),
              content,
          )
          content = re.sub(
              r'(npmDepsHash = ")[^"]+(";)',
              lambda m: m.group(1) + npm_deps_hash + m.group(2),
              content,
          )

          with open(derivation, "w") as f:
              f.write(content)

          subprocess.run(["git", "add", derivation, lockfile], check=True)

          print(f"Updated {derivation} from {current} to {latest}.")
          print("Stage the change with: git add pkgs/actual-cli/default.nix pkgs/actual-cli/package-lock.json")
        '';

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

        # Queries the fastmail-rules-cli main branch for the latest commit,
        # prefetches the source and vendor hashes, and rewrites the derivation.
        # No releases exist yet, so we track HEAD of main. Must be run from
        # the root of the flake checkout.
        updateFastmailRulesCliScript = pkgs.writeText "update-fastmail-rules-cli.py" ''
          import json
          import re
          import subprocess
          import sys
          import os
          import urllib.request

          DERIVATION = "pkgs/fastmail-rules-cli/default.nix"
          BRANCH_API = "https://api.github.com/repos/dvcrn/fastmail-rules-cli/branches/main"

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          print("Fetching fastmail-rules-cli latest commit...")
          request = urllib.request.Request(
              BRANCH_API,
              headers={"Accept": "application/vnd.github+json", "User-Agent": "nix-update-fastmail-rules-cli"},
          )
          with urllib.request.urlopen(request) as response:
              branch = json.load(response)

          latest_sha = branch["commit"]["sha"]
          latest_date = branch["commit"]["commit"]["committer"]["date"][:10]
          latest_version = f"unstable-{latest_date}"

          with open(DERIVATION) as f:
              content = f.read()

          current_rev = re.search(r'rev = "([^"]+)"', content).group(1)
          current_version = re.search(r'version = "([^"]+)"', content).group(1)
          print(f"Current: {current_version} ({current_rev[:7]})")
          print(f"Latest:  {latest_version} ({latest_sha[:7]})")

          if current_rev == latest_sha:
              print("Already up to date.")
              sys.exit(0)

          print("Updating derivation...")
          content = content.replace(f'version = "{current_version}"', f'version = "{latest_version}"', 1)
          content = content.replace(f'rev = "{current_rev}"', f'rev = "{latest_sha}"', 1)

          # Clear both hashes so nix build will recompute them.
          # Source hash is inside the fetchFromGitHub block (4-space indent).
          content = re.sub(
              r'(\s{4}hash = ")[^"]+(";)',
              r'\1\2',
              content
          )
          # vendorHash is at the top level (2-space indent).
          content = re.sub(
              r'(  vendorHash = ")[^"]+(";)',
              r'\1\2',
              content
          )

          with open(DERIVATION, "w") as f:
              f.write(content)

          # Stage the change so Nix can see the updated file.
          subprocess.run(["git", "add", DERIVATION], check=True)

          print(f"Building to obtain new hashes...")
          result = subprocess.run(
              ["nix", "build", ".#fastmail-rules-cli"],
              capture_output=True, text=True
          )

          # nix build will fail with the correct hashes in stderr.
          combined = result.stdout + result.stderr

          src_hash_match = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", combined)
          vendor_hash_match = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", combined[combined.find("vendor"):] if "vendor" in combined else combined)

          if not src_hash_match:
              print("error: could not determine new source hash", file=sys.stderr)
              print(combined, file=sys.stderr)
              sys.exit(1)

          new_src_hash = src_hash_match.group(1)

          # Reread the derivation (it may have been rebuilt).
          with open(DERIVATION) as f:
              content = f.read()

          # Insert source hash into the first empty hash = ""
          content = content.replace('hash = ""', f'hash = "{new_src_hash}"', 1)

          # Rebuild to get vendorHash now that source hash is correct.
          with open(DERIVATION, "w") as f:
              f.write(content)
          subprocess.run(["git", "add", DERIVATION], check=True)

          print(f"Building to obtain vendor hash...")
          result = subprocess.run(
              ["nix", "build", ".#fastmail-rules-cli"],
              capture_output=True, text=True
          )
          combined = result.stdout + result.stderr

          if result.returncode == 0:
              print("Build succeeded — vendor hash already resolved.")
          else:
              vendor_match = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", combined)
              if vendor_match:
                  new_vendor_hash = vendor_match.group(1)
                  with open(DERIVATION) as f:
                      content = f.read()
                  content = content.replace('vendorHash = ""', f'vendorHash = "{new_vendor_hash}"')
                  with open(DERIVATION, "w") as f:
                      f.write(content)
                  subprocess.run(["git", "add", DERIVATION], check=True)

                  # Final build to confirm.
                  print("Running final build to confirm...")
                  result = subprocess.run(
                      ["nix", "build", ".#fastmail-rules-cli"],
                      capture_output=True, text=True
                  )
                  if result.returncode != 0:
                      print("error: final build failed", file=sys.stderr)
                      print(result.stdout + result.stderr, file=sys.stderr)
                      sys.exit(1)
              else:
                  print("error: could not determine vendor hash", file=sys.stderr)
                  print(combined, file=sys.stderr)
                  sys.exit(1)

          print(f"Updated {DERIVATION} from {current_version} to {latest_version}.")
          print("Stage the change with: git add pkgs/fastmail-rules-cli/default.nix")
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

        # Queries the ds4 GitHub repository for the latest commit on main,
        # prefetches the source hash, and rewrites the derivation with the
        # new rev (full SHA) and version date. No releases exist yet, so we
        # track HEAD of main. Must be run from the root of the flake checkout.
        updateDs4Script = pkgs.writeText "update-ds4.py" ''
          import json
          import re
          import subprocess
          import sys
          import os
          import urllib.request

          DERIVATION = "pkgs/ds4/default.nix"
          BRANCH_API = "https://api.github.com/repos/antirez/ds4/branches/main"

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          print("Fetching ds4 latest commit...")
          request = urllib.request.Request(
              BRANCH_API,
              headers={"Accept": "application/vnd.github+json", "User-Agent": "nix-update-ds4"},
          )
          with urllib.request.urlopen(request) as response:
              branch = json.load(response)

          latest_sha = branch["commit"]["sha"]
          latest_date = branch["commit"]["commit"]["committer"]["date"][:10]
          latest_version = f"unstable-{latest_date}"

          with open(DERIVATION) as f:
              content = f.read()

          current_rev = re.search(r'rev = "([^"]+)"', content).group(1)
          current_version = re.search(r'version = "([^"]+)"', content).group(1)
          print(f"Current: {current_version} ({current_rev[:7]})")
          print(f"Latest:  {latest_version} ({latest_sha[:7]})")

          if current_rev == latest_sha:
              print("Already up to date.")
              sys.exit(0)

          # Prefetch hash using nix-prefetch-github.
          # nix-prefetch-url / prefetch-file won't work for GitHub tarballs
          # that need authentication or are private, so we use
          # nix-prefetch-github or nix store prefetch-file with the archive URL.
          archive_url = f"https://github.com/antirez/ds4/archive/{latest_sha}.tar.gz"
          print("Prefetching source hash...")
          result = subprocess.run(
              ["nix", "store", "prefetch-file", archive_url],
              capture_output=True, text=True
          )
          hash_match = re.search(r"hash '([^']+)'", result.stdout + result.stderr)
          if not hash_match:
              print(f"error: could not fetch hash for {archive_url}", file=sys.stderr)
              sys.exit(1)

          new_hash = hash_match.group(1)

          content = content.replace(f'version = "{current_version}"', f'version = "{latest_version}"', 1)
          content = content.replace(f'rev = "{current_rev}"', f'rev = "{latest_sha}"', 1)
          content = re.sub(
              r'(hash = ")[^"]+(")',
              lambda m: m.group(1) + new_hash + m.group(2),
              content
          )

          with open(DERIVATION, "w") as f:
              f.write(content)

          print(f"Updated {DERIVATION} from {current_version} to {latest_version}.")
          print("Stage the change with: git add pkgs/ds4/default.nix")
        '';

        # Resolves the commit that Kagi's Flatpak repository currently exposes
        # for the Orion beta ref, and rewrites the derivation with that commit,
        # its version, and its output hash.
        #
        # Orion has no release feed and no versioned download URL, so the
        # OSTree repository is the only update source.  Two properties of
        # OSTree make this cheap: commit metadata can be fetched without any
        # content, and a partial pull can retrieve just the AppStream metainfo
        # file that carries the version number.  Both cost a couple of
        # kilobytes, so the 75 MiB content pull only happens once the commit
        # has actually moved.
        #
        # Must be run from the root of the flake checkout.
        updateOrionBrowserScript = pkgs.writeText "update-orion-browser.py" ''
          import os
          import re
          import shutil
          import subprocess
          import sys
          import tempfile
          import xml.etree.ElementTree as ElementTree

          DERIVATION = "pkgs/orion-browser/default.nix"
          REMOTE_URL = "https://flatpak.orionbrowser.com/repo/beta/"
          REMOTE_REF = "app/com.kagi.Orion/x86_64/beta"
          METAINFO_SUBPATH = "/export/share/metainfo"
          METAINFO_FILE = "com.kagi.Orion.metainfo.xml"

          if len(sys.argv) != 3:
              print("usage: update-orion-browser.py <ostree> <nix>", file=sys.stderr)
              sys.exit(1)

          ostree, nix = sys.argv[1], sys.argv[2]

          if not os.path.exists(DERIVATION):
              print("error: run this script from the root of the flake", file=sys.stderr)
              sys.exit(1)

          with open(DERIVATION) as f:
              content = f.read()

          def find(pattern, description):
              match = re.search(pattern, content)
              if not match:
                  print(f"error: could not find {description} in derivation", file=sys.stderr)
                  sys.exit(1)
              return match.group(1)

          current_version = find(r'version = "([^"]+)"', "current version")
          current_commit = find(r'ostreeCommit = "([^"]+)"', "pinned OSTree commit")
          current_hash = find(r'outputHash = "([^"]+)"', "current output hash")

          workdir = tempfile.mkdtemp(prefix="update-orion-browser.")
          repo = os.path.join(workdir, "repo")

          def run_ostree(*arguments):
              result = subprocess.run(
                  [ostree, f"--repo={repo}"] + list(arguments),
                  capture_output=True,
                  text=True,
              )
              if result.returncode != 0:
                  print(f"error: ostree {' '.join(arguments)} failed:", file=sys.stderr)
                  print(result.stderr, file=sys.stderr)
                  shutil.rmtree(workdir, ignore_errors=True)
                  sys.exit(1)
              return result.stdout

          try:
              run_ostree("init", "--mode=archive-z2")
              run_ostree("remote", "add", "--no-gpg-verify", "orion", REMOTE_URL)

              print("Resolving the current commit for the Orion beta ref...")
              run_ostree("pull", "--commit-metadata-only", "orion", REMOTE_REF)
              log = run_ostree("log", f"orion:{REMOTE_REF}")

              match = re.search(r"^commit ([0-9a-f]{64})$", log, re.MULTILINE)
              if not match:
                  print("error: could not parse commit from ostree log", file=sys.stderr)
                  sys.exit(1)

              latest_commit = match.group(1)

              print(f"Current: {current_version} ({current_commit[:12]})")
              print(f"Latest:  {latest_commit[:12]}")

              if latest_commit == current_commit:
                  print("Already up to date.")
                  sys.exit(0)

              # The version lives only in the app's own AppStream metainfo file;
              # the repository's appstream2 ref carries no release versions.
              print("Fetching version metadata...")
              run_ostree(
                  "pull",
                  f"--subpath={METAINFO_SUBPATH}",
                  "orion",
                  f"{REMOTE_REF}@{latest_commit}",
              )

              metainfo_dir = os.path.join(workdir, "metainfo")
              run_ostree(
                  "checkout",
                  "--user-mode",
                  f"--subpath={METAINFO_SUBPATH}",
                  latest_commit,
                  metainfo_dir,
              )

              releases = ElementTree.parse(
                  os.path.join(metainfo_dir, METAINFO_FILE)
              ).getroot().find("releases")

              if releases is None or releases.find("release") is None:
                  print("error: no release entry in metainfo", file=sys.stderr)
                  sys.exit(1)

              latest_version = releases.find("release").get("version")
              print(f"Latest version: {latest_version}")

              print("Fetching content (this pulls the full application tree)...")
              run_ostree("pull", "--depth=0", "orion", f"{REMOTE_REF}@{latest_commit}")

              checkout = os.path.join(workdir, "checkout")
              run_ostree("checkout", "--user-mode", latest_commit, checkout)

              # An `ostree checkout --user-mode` here produces a tree identical
              # to the one the fixed-output derivation builds, so hashing it
              # directly avoids a throwaway build to discover the hash.
              result = subprocess.run(
                  [nix, "hash", "path", "--sri", "--type", "sha256", checkout],
                  capture_output=True,
                  text=True,
              )
              if result.returncode != 0:
                  print("error: could not hash the checkout:", file=sys.stderr)
                  print(result.stderr, file=sys.stderr)
                  sys.exit(1)

              new_hash = result.stdout.strip()
          finally:
              shutil.rmtree(workdir, ignore_errors=True)

          content = content.replace(
              f'version = "{current_version}"', f'version = "{latest_version}"', 1
          )
          content = content.replace(
              f'ostreeCommit = "{current_commit}"', f'ostreeCommit = "{latest_commit}"', 1
          )
          content = content.replace(
              f'outputHash = "{current_hash}"', f'outputHash = "{new_hash}"', 1
          )

          with open(DERIVATION, "w") as f:
              f.write(content)

          print(f"Updated {DERIVATION} from {current_version} to {latest_version}.")
          print("Stage the change with: git add pkgs/orion-browser/default.nix")
        '';
      in
      {
        update-actual-cli = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-actual-cli" ''
            exec ${pkgs.python3}/bin/python3 ${updateActualCliScript} \
              pkgs/actual-cli/default.nix \
              pkgs/actual-cli/package-lock.json \
              ${pkgs.nodejs_22}/bin/npm \
              ${pkgs.prefetch-npm-deps}/bin/prefetch-npm-deps \
              ${pkgs.nix}/bin/nix
          '');
        };

        update-deadbranch = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-deadbranch" ''
            exec ${pkgs.nix-update}/bin/nix-update --flake deadbranch --version-regex 'v(.*)'
          '');
        };

        update-fastmail = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-fastmail" ''
            exec ${pkgs.nix-update}/bin/nix-update --flake fastmail
          '');
        };

        update-fastmail-cli = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-fastmail-cli" ''
            exec ${pkgs.nix-update}/bin/nix-update --flake fastmail-cli --version-regex 'v(.*)'
          '');
        };

        update-ds4 = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-ds4" ''
            exec ${pkgs.python3}/bin/python3 ${updateDs4Script}
          '');
        };

        update-fastmail-rules-cli = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-fastmail-rules-cli" ''
            exec ${pkgs.python3}/bin/python3 ${updateFastmailRulesCliScript}
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

        update-orion-browser = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-orion-browser" ''
            exec ${pkgs.python3}/bin/python3 ${updateOrionBrowserScript} \
              ${pkgs.ostree}/bin/ostree \
              ${pkgs.nix}/bin/nix
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

            for app in update-actual-cli update-deadbranch update-ds4 update-fastmail update-fastmail-cli update-fastmail-rules-cli update-freecad-weekly update-godot-dev update-msty-studio update-orion-browser update-textgen update-vibe update-whispering; do
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
