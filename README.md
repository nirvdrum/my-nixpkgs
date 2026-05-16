# my-nixpkgs

A personal Nix flake containing packages not yet available in nixpkgs. The goal is to iterate quickly here and upstream packages to nixpkgs when they're stable and broadly useful.

## Packages

| Name               | Description                                                                              |
|--------------------|------------------------------------------------------------------------------------------|
| `claude-desktop`   | Anthropic's Claude AI desktop application for Linux (unofficial package)                  |
| `deadbranch`       | CLI tool for safely cleaning up stale git branches                                       |
| `freecad-weekly`   | FreeCAD pre-release builds (RC and weekly), wrapped from the official AppImage            |
| `godot-dev`        | Godot game engine development/beta/RC builds (pre-built binary)                          |
| `godot-dev-mono`   | Godot game engine development/beta/RC builds with C#/.NET support (pre-built binary)     |
| `msty-studio`      | Desktop application for running and managing local AI models                              |
| `orion-browser`    | Web browser built by Kagi, using WebKitGTK (early beta, x86_64-linux only)               |
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

**claude-desktop** tracks releases from the unofficial
[claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) project, which
repackages Anthropic's Claude Desktop as AppImages for Linux. To update to the latest release:

```
nix run .#update-claude-desktop
```

This queries the GitHub releases API, finds the newest release tag (format
`v<wrapper>+claude<app>`), prefetches the x86_64 AppImage hash, and rewrites
`pkgs/claude-desktop/default.nix`.

**deadbranch** tracks GitHub release tags from the [deadbranch repository](https://github.com/armgabrielyan/deadbranch).
To update to the latest release:

```
nix run .#update-deadbranch
```

This uses `nix-update` under the hood. It queries the deadbranch GitHub releases API,
finds the newest `v*` tag, and rewrites the `version` and `hash` fields in
`pkgs/deadbranch/default.nix` automatically.

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

**orion-browser** tracks the rolling `latest.flatpak` build from
[orionbrowser.com](https://orionbrowser.com). Since the URL is rolling and has no version tag,
updates require a manual hash refresh. To update:

```
# Set hash = "" in pkgs/orion-browser/default.nix, then:
git add pkgs/orion-browser/default.nix && nix build .#orion-browser 2>&1 | grep -oP 'sha256-\S+'
# Copy the hash back into the derivation and update the version date.
```

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
