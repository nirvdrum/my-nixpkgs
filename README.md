# my-nixpkgs

A personal Nix flake containing packages not yet available in nixpkgs. The goal is to iterate quickly here and upstream packages to nixpkgs when they're stable and broadly useful.

## Packages

| Name               | Description                                                                              |
|--------------------|------------------------------------------------------------------------------------------|
| `actual-cli`       | Command-line interface for Actual Budget (binary: `actual`)                              |
| `deadbranch`       | CLI tool for safely cleaning up stale git branches                                       |
| `fastmail`         | CLI for Fastmail email, calendars, events, and todos via JMAP and CalDAV                 |
| `fastmail-cli`     | Command-line interface for Fastmail using JMAP (binary: `fm`)                            |
| `fastmail-rules-cli` | CLI for managing Fastmail mail rules and Sieve scripts via JMAP (binary: `fastmail-sieve`) |
| `ds4`              | DeepSeek V4 Flash local inference engine (Metal, aarch64-darwin only)                    |
| `freecad-weekly`   | FreeCAD pre-release builds (RC and weekly), wrapped from the official AppImage            |
| `godot-dev`        | Godot game engine development/beta/RC builds (pre-built binary)                          |
| `godot-dev-mono`   | Godot game engine development/beta/RC builds with C#/.NET support (pre-built binary)     |
| `msty-studio`      | Desktop application for running and managing local AI models                              |
| `orion-browser`    | Web browser built by Kagi, using WebKitGTK (early beta, x86_64-linux only)               |
| `textgen`          | Local LLM inference UI — CPU default (Linux x86_64) or ARM64 (macOS)                     |
| `textgen-rocm`     | Local LLM inference UI — ROCm variant (Linux x86_64 only)                                |
| `textgen-vulkan`   | Local LLM inference UI — Vulkan variant (Linux x86_64 only)                              |
| `unsloth-desktop`  | Native desktop app for running and training LLMs and diffusion models locally            |
| `vibe`             | Easy Linux virtual machine on macOS to sandbox LLM agents (aarch64-darwin only)           |
| `whispering`       | Local-first speech-to-text: press shortcut, speak, get text (open source)                |

## Common tasks

### List available packages

```
nix flake show
```

### Build a package

```
nix build .#freecad-weekly
```

The result is linked to `./result` in the repo root.

### Run a package without installing it

```
nix run .#freecad-weekly
```

### Install a package into your profile

```
nix profile install .#freecad-weekly
```

### Use a package in a NixOS configuration

Add this flake as an input and reference the package in your configuration:

```nix
# flake.nix (your system flake)
inputs.my-nixpkgs.url = "github:youruser/my-nixpkgs";

# configuration.nix (or wherever you declare packages)
environment.systemPackages = [
  inputs.my-nixpkgs.packages.${pkgs.system}.freecad-weekly
];
```

### Update a package to its latest release

Each package that tracks a moving upstream target has a corresponding update app.

**actual-cli** tracks the latest stable version of `@actual-app/cli` published to the
[npm registry](https://www.npmjs.com/package/@actual-app/cli). Because the published
tarball ships a bundled build output and no lockfile, the updater regenerates a
production `package-lock.json`, then prefetches the source and `npmDepsHash` values
and rewrites both `pkgs/actual-cli/default.nix` and `pkgs/actual-cli/package-lock.json`.
Run the following from the repo root:

```
nix run .#update-actual-cli
```

This installs dependencies into a throwaway directory using the same `nodejs_22` npm
that the build uses, so the regenerated lockfile matches what `fetchNpmDeps` resolves
at build time and future updates stay minimal diffs.

**freecad-weekly** tracks FreeCAD `weekly-YYYY.MM.DD` release tags. To update to the
latest weekly build, run the following from the repo root:

```
nix run .#update-freecad-weekly
```

This uses `nix-update` under the hood. It queries the FreeCAD GitHub releases API,
finds the newest `weekly-*` tag, and rewrites the `version` and `hash` fields in
`pkgs/freecad-weekly/default.nix` automatically.

> **Note:** While FreeCAD is still in the RC phase (before 1.1 stable ships), weekly
> builds may not exist yet. To bump between RC versions, run `nix-update` directly
> without the version filter:
>
> ```
> nix-update --flake freecad-weekly
> ```

**fastmail** tracks GitHub release tags from the [shareup/fastmail repository](https://github.com/shareup/fastmail).
To update to the latest release:

```
nix run .#update-fastmail
```

This uses `nix-update` under the hood. It queries the GitHub releases API,
finds the newest tag, and rewrites the `version`, `src.hash`, and `vendorHash` fields in
`pkgs/fastmail/default.nix` automatically.

**fastmail-cli** tracks GitHub release tags from the [vicyap/fastmail-cli repository](https://github.com/vicyap/fastmail-cli).
To update to the latest release:

```
nix run .#update-fastmail-cli
```

This uses `nix-update` under the hood. It queries the GitHub releases API,
finds the newest `v*` tag, and rewrites the `version`, `src.hash`, and `vendorHash` fields
in `pkgs/fastmail-cli/default.nix` automatically.

The derivation also installs shell completions (bash, zsh, fish), man pages, and agent skills
(`.agents/skills/fastmail/`) to `$out/share/fastmail-cli/`.

**fastmail-rules-cli** tracks the latest commit on `main` from the
[dvcrn/fastmail-rules-cli repository](https://github.com/dvcrn/fastmail-rules-cli).
The project has no releases yet, so the pinned commit serves as the version.
To update to the latest commit:

```
nix run .#update-fastmail-rules-cli
```

This queries the GitHub branches API, determines the current HEAD SHA and date,
prefetches source and vendor hashes, and rewrites `pkgs/fastmail-rules-cli/default.nix`.

**deadbranch** tracks GitHub release tags from the [deadbranch repository](https://github.com/armgabrielyan/deadbranch).
To update to the latest release:

```
nix run .#update-deadbranch
```

This uses `nix-update` under the hood. It queries the deadbranch GitHub releases API,
finds the newest `v*` tag, and rewrites the `version` and `hash` fields in
`pkgs/deadbranch/default.nix` automatically.

**ds4** tracks the latest commit on `main` branch from the [ds4 GitHub repository](https://github.com/antirez/ds4).

Builds five Metal-backed binaries (ds4, ds4-server, ds4-agent, ds4-bench, ds4-eval) for aarch64-darwin from the upstream ds4 repository.  The project has no releases yet, so the pinned commit serves as the version.

A compat header bridges the gap between nixpkgs' macOS SDK 14.4 and the macOS 15.0 Metal APIs used by ds4 (MTLResidencySetDescriptor, MTLMathModeSafe, missing protocol selectors). Metal shader source files are shipped in $out/share/ds4/metal/ with wrapper scripts that set the working directory so the engine finds them at runtime.

To update to the latest commit:

```
nix run .#update-ds4
```

This queries the GitHub branches API, determines the current HEAD SHA and date,
prefetches the source tarball hash, and rewrites `pkgs/ds4/default.nix`.

**godot-dev** and **godot-dev-mono** track pre-release builds from the
[godot-builds](https://github.com/godotengine/godot-builds) GitHub repository.
To update to the latest dev/beta/RC snapshot in the current development cycle:

```
nix run .#update-godot-dev
```

This queries the GitHub releases API for the newest `dev`, `beta`, or `rc` tag in the
configured base version series (e.g., 4.7), prefetches fresh hashes for the standard
and mono variants on both Linux x86_64 and macOS (universal binary), and rewrites
`pkgs/godot-dev/default.nix`.

> **Note:** When a new major development cycle begins (e.g., 4.8), update the
> `baseVersion` field in the derivation manually before running the update script.

**textgen** tracks release tags from the [oobabooga/textgen](https://github.com/oobabooga/textgen) GitHub
repository.  To update to the latest release:

```
nix run .#update-textgen
```

This queries the GitHub releases API, finds the newest `v<X.Y>` tag, prefetches
fresh hashes for all four variant assets (linux-cpu, linux-vulkan, linux-rocm, and
macos-arm64), and rewrites `pkgs/textgen/default.nix`.

**msty-studio** tracks versions published on the [Msty changelog](https://msty.ai/changelog).
To update to the latest release:

```
nix run .#update-msty-studio
```

This fetches the changelog, determines the latest version, prefetches new hashes for
both the Linux AppImage and macOS DMG, and rewrites `pkgs/msty-studio/default.nix`.

**vibe** tracks date+SHA release tags from the [Vibe GitHub repository](https://github.com/lynaghk/vibe).
To update to the latest release:

```
nix run .#update-vibe
```

This queries the GitHub releases API, finds the newest date+SHA tag, prefetches the
macOS ARM64 zip hash, and rewrites `pkgs/vibe/default.nix`.

**orion-browser** is pulled from Kagi's Flatpak repository at
`https://flatpak.orionbrowser.com/repo/beta/`, which is a plain OSTree repository. Kagi stopped publishing per-version `.flatpak` bundles after 0.3.0, so there is no versioned URL to fetch and no release feed to poll; the derivation instead pins the OSTree commit that the moving `beta` ref pointed at when the version was cut. To update to the latest beta build:

```
nix run .#update-orion-browser
```

This resolves the commit the `beta` ref currently points at and exits early if it matches the pinned one. Otherwise it reads the new version out of the application's AppStream metainfo, pulls the content, hashes the checkout, and rewrites `version`, `ostreeCommit`, and `outputHash` in `pkgs/orion-browser/default.nix`.

Two OSTree details keep the common case cheap: commit metadata can be fetched without any content, and `--subpath` retrieves just the metainfo file carrying the version number. Both cost a couple of kilobytes, so the ~75 MiB content pull only happens when the commit has actually moved. Note that the version number appears only in the application's own `com.kagi.Orion.metainfo.xml` — the repository's `appstream2` ref carries release entries with no version attributes, and the OSTree commit message does not record it either.

**whispering** tracks Whispering releases from the
[EpicenterHQ/epicenter](https://github.com/EpicenterHQ/epicenter) monorepo.  The
monorepo also publishes non-Whispering tags (e.g. `models/<name>` and `_assets`),
so the updater filters releases to those that match `v<X.Y.Z>` *and* ship a
Whispering AppImage asset.  To update to the latest release:

```
nix run .#update-whispering
```

This queries the GitHub releases API, finds the newest qualifying release, prefetches
fresh hashes for both the Linux x86_64 AppImage and the macOS aarch64 `.app` tarball,
and rewrites `pkgs/whispering/default.nix`.

**unsloth-desktop** tracks Unsloth Desktop releases from the [unslothai/unsloth](https://github.com/unslothai/unsloth) GitHub repository. Most releases in that repository are model announcements (e.g. "Qwen3.8-27B") rather than app versions, so the updater filters releases to those whose tag matches `v<X.Y.Z>-beta` *and* ship an `Unsloth-Desktop-*` asset. To update to the latest release:

```
nix run .#update-unsloth-desktop
```

This queries the GitHub releases API, finds the newest qualifying release, prefetches fresh hashes for both the Linux x86_64 AppImage and the macOS DMG, and rewrites `pkgs/unsloth-desktop/default.nix`.

### Add a new package

1. Create a directory under `pkgs/`:

   ```
   pkgs/<package-name>/default.nix
   ```

2. Write the derivation in `default.nix`.

3. Expose it in `flake.nix`:

   ```nix
   packages.${system}.<package-name> = pkgs.callPackage ./pkgs/<package-name> { };
   ```

4. Stage the new files (`git add`) before building — Nix flakes only see tracked files.

5. Build with `nix build .#<package-name>` to confirm it works.

## Repo structure

```
.
├── flake.nix            # Flake definition; exposes packages and update apps
├── flake.lock           # Pinned input versions
├── pkgs/
│   └── <package-name>/
│       └── default.nix  # One derivation per directory
└── README.md
```

## Upstreaming to nixpkgs

When a package is stable and broadly useful, it belongs in nixpkgs rather than here.
See the checklist in `CLAUDE.md` before opening a PR.
