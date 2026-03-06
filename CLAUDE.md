# Nix Packaging Strategy

## Goal

Package software not yet available in nixpkgs for use on NixOS and macOS (via nix-darwin or standalone Nix). Where it makes sense, upstream contributions to nixpkgs so everyone benefits.

## Architecture Decision: Personal Flake → Nixpkgs (Skip NUR)

### Approach

1. **Personal flake (this repo):** All custom derivations live here. No external review process, no dependencies on third-party infrastructure. Iterate fast, break things, fix them.
2. **Upstream to nixpkgs:** When a package is stable, generally useful, and meets nixpkgs standards, open a PR to [nixpkgs](https://github.com/NixOS/nixpkgs). This gets binary cache coverage via Hydra and reaches the widest audience.
3. **Skip NUR:** The Nix User Repository adds registration and structural overhead without meaningful benefit for a small personal collection. NUR is best suited for maintainers with a large corpus of packages that won't land in nixpkgs but should be discoverable by others.

### Why This Order

- **Personal flake** gives maximum velocity. No review gates, no CI to appease, no one else depends on it.
- **Nixpkgs** is where impact is highest. Users get binary cache hits instead of source builds. Packages are tested across platforms by Hydra. Discoverability is automatic via `nix search` and search.nixos.org.
- **NUR** exists as a pressure valve for packages that can't or won't enter nixpkgs (too niche, unfree, opinionated, experimental, or the maintainer prefers autonomy). It's a registry of personal repos — useful for discovery, but not a substitute for nixpkgs and not necessary if the goal is personal use plus upstreaming.

## Why NUR Exists (Context)

Nixpkgs has intentional friction: quality standards, review processes, policies on unfree software, restrictions on vendored/bundled dependencies, and expectations around maintainer responsiveness. NUR provides a way for the community to share packages that don't fit through those gates. Common reasons packages stay in NUR permanently:

- Too niche to justify nixpkgs review effort
- Unfree or proprietary with licensing complications
- Experimental or frequently breaking
- Opinionated packaging choices that conflict with nixpkgs conventions
- Maintainer prefers autonomy over nixpkgs process

Some NUR packages are staging areas that eventually land in nixpkgs, but many are permanent residents.

## Repo Structure

This repo is a Nix flake. Recommended layout:

```
.
├── CLAUDE.md
├── flake.nix
├── flake.lock
├── pkgs/
│   ├── <package-name>/
│   │   └── default.nix
│   └── ...
└── overlays/
    └── default.nix       # optional: expose packages as a nixpkgs overlay
```

### flake.nix Conventions

- Expose packages under `packages.<system>.<name>` for both `x86_64-linux` and `aarch64-darwin` (and any other systems in use).
- Use `nixpkgs` as the primary input.
- Keep each package in its own directory under `pkgs/` for easy extraction when upstreaming to nixpkgs.

## Adding a New Derivation

### General checklist

- Create `pkgs/<name>/default.nix` and expose it in `flake.nix` under `packages.${system}.<name>`.
- **Stage new files with `git add` before running `nix build`.** Nix flakes evaluate the Git tree, so untracked files are invisible and the build will fail with a misleading path-not-found error.
- **Hash discovery:** Set `hash = "";` initially, run `nix build`, and copy the correct SRI hash from the mismatch error. Do not guess or derive hashes manually.
- If the package tracks a frequently-updated upstream (RCs, weekly builds, etc.), add a corresponding `apps.${system}.update-<name>` entry in `flake.nix` that calls `nix-update` with the appropriate `--version-regex` filter. This makes updates a single `nix run` invocation rather than a manual process.
- **Update `README.md`** whenever a package is added or removed. The README contains a package table and per-package update instructions that must stay in sync with what `flake.nix` actually exposes. The package table should be sorted lexicographically and its column separators should be aligned for readability in plain text.

### Additional checklist for AppImage packages

AppImage packages use `appimageTools.wrapType2` and require an extraction step to install desktop entries and icons. Before writing `extraInstallCommands`:

- Inspect the extracted store path (printed in the build output, or found under `/nix/store/*<name>*extracted*`) to confirm the exact desktop file name and icon paths — they often differ from what upstream documentation suggests.
- Read the `.desktop` file to find the actual `Exec=` line before writing the `substituteInPlace` call. AppImage desktop files frequently use `Exec=AppRun` rather than the binary name.

## Upstreaming Checklist

Before opening a nixpkgs PR for a package from this repo:

- [ ] Package builds on all intended platforms (at minimum: `x86_64-linux`, `aarch64-darwin`)
- [ ] `meta` attribute set is complete (`description`, `homepage`, `license`, `maintainers`, `platforms`)
- [ ] No vendored dependencies that nixpkgs already provides
- [ ] Passes `nix-shell -p nixpkgs-review --run "nixpkgs-review rev HEAD"` or equivalent local testing
- [ ] Follows [nixpkgs contributing guide](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md)
- [ ] Add yourself as a maintainer in `maintainers/maintainer-list.nix` if not already present

## Useful References

- [Nixpkgs manual — packaging guide](https://nixos.org/manual/nixpkgs/stable/#chap-quick-start)
- [Nixpkgs contributing guide](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md)
- [NUR README](https://github.com/nix-community/NUR) (for future reference if the collection grows)
- [nix.dev tutorials](https://nix.dev/)
