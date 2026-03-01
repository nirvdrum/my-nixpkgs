# my-nixpkgs

A personal Nix flake containing packages not yet available in nixpkgs. The goal is to iterate quickly here and upstream packages to nixpkgs when they're stable and broadly useful.

## Packages

| Name | Description |
|------|-------------|
| `freecad-weekly` | FreeCAD pre-release builds (RC and weekly), wrapped from the official AppImage |

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
