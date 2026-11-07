# Package reference

One row per directory under `pkgs/`. The display name is the one used in commit subjects; keep using it so `git log` reads consistently. The attribute column lists every flake output built from that directory, since a single updater run can change several of them. The smoke test column is the quickest check that proves the new version actually runs, not just builds.

This table is a snapshot. When a package is added, removed, or its binary changes, the derivation and `flake.nix` are the source of truth, so update this file to match rather than trusting it blindly.

| Directory            | Display name       | Attributes (x86_64-linux)                             | Darwin only | Kind                       | Smoke test                                                                 |
|----------------------|--------------------|-------------------------------------------------------|-------------|----------------------------|----------------------------------------------------------------------------|
| `actual-cli`         | Actual CLI         | `actual-cli`                                          |             | npm CLI                    | `actual --version`                                                         |
| `deadbranch`         | deadbranch         | `deadbranch`                                          |             | Rust CLI                   | `deadbranch --version`                                                     |
| `ds4`                | DS4                | `ds4`                                                 |             | native inference server    | `ds4 --help`                                                               |
| `fastmail`           | Fastmail           | `fastmail`                                            |             | Go CLI                     | `fastmail --help`                                                          |
| `fastmail-cli`       | Fastmail CLI       | `fastmail-cli`                                        |             | Go CLI (binary `fm`)       | `fm --version`                                                             |
| `fastmail-rules-cli` | Fastmail Rules CLI | `fastmail-rules-cli`                                  |             | Go CLI (`fastmail-sieve`)  | `fastmail-sieve --help`                                                    |
| `freecad-weekly`     | FreeCAD Weekly     | `freecad-weekly`                                      |             | AppImage GUI               | `smoke-gui.sh freecad-weekly`                                              |
| `godot-dev`          | Godot              | `godot-dev`, `godot-dev-mono`                         |             | prebuilt GUI binary        | `godot-dev --version` (prints the tag and exits; no display needed)        |
| `h3c`                | H3C                | none                                                  | yes         | native inference CLI       | cannot run on Linux; evaluate only                                         |
| `msty-studio`        | Msty Studio        | `msty-studio`                                         |             | AppImage GUI (Electron)    | `smoke-gui.sh msty-studio`                                                 |
| `orion-browser`      | Orion              | `orion-browser`                                       |             | WebKitGTK GUI              | `smoke-gui.sh orion-browser`                                               |
| `strix-llama-cpp`    | Strix Llama        | `strix-llama-cpp-rocm`, `strix-llama-cpp-vulkan`      |             | native inference server    | `llama-server --version` for each variant                                  |
| `textgen`            | Textgen            | `textgen`, `textgen-rocm`, `textgen-vulkan`           |             | Python web UI wrapper      | `textgen --help` for each variant                                          |
| `truenas-mcp`        | TrueNAS MCP        | `truenas-mcp`                                         |             | Go MCP server              | `truenas-mcp --version`                                                    |
| `unsloth-desktop`    | Unsloth Desktop    | `unsloth-desktop`                                     |             | AppImage GUI in FHS env    | `smoke-gui.sh unsloth-desktop 30` (slow to start)                          |
| `vibe`               | Vibe               | none                                                  | yes         | macOS VM tool              | cannot run on Linux; evaluate only                                         |
| `whispering`         | Whispering         | `whispering`                                          |             | AppImage GUI                | `smoke-gui.sh whispering`                                                  |
| `wyoming-openai`     | Wyoming OpenAI     | `wyoming-openai`                                      |             | Python server              | `wyoming-openai --help` (no `--version` flag)                                                 |

## Version string quirks

- Packages tracking a branch rather than releases (`ds4`, `strix-llama-cpp`, `fastmail-rules-cli`, `h3c`) use `unstable-YYYY-MM-DD`. Commit subjects drop the `unstable-` prefix: "Update DS4 from 2026-10-07 -> 2026-11-01."
- `godot-dev` builds its version from `baseVersion` and `preLabel`, so the diff shows `preLabel` changing. The subject uses the full label: "Update Godot from 4.8-beta1 to 4.8-beta2."
- `freecad-weekly` stores `YYYY.MM.DD` with dots to match the upstream tag, but every commit subject in history writes it with dashes: "Update FreeCAD Weekly from 2026-10-07 -> 2026-10-28." Keep the dashes so the log stays uniform.
- `wyoming-openai` has several `version =` lines because it vendors Python dependencies; only the last one (`wyoming_openai`) is the package version. Its updater also moves any pinned wheel that the new release's requirements rule out, so the diff may show several versions changing under one commit. It cannot update the source-built `websockets` and `jiter` overrides, so it names them and exits non-zero when they fall out of range, with everything else already written. Update those by hand, using `hash = ""` to discover both the source and vendor hashes.
- `deadbranch` has a literal `tag = "v0.3.0"` that is not derived from `version`. If the updater bumps `version` without touching `tag`, the build will silently keep fetching the old source. Check that the tag moved too.

## Evaluating Darwin-only packages from Linux

You cannot build `h3c` or `vibe` on Linux, but you can confirm the derivation still evaluates and that the updater wrote a well-formed file:

```
nix eval --raw .#packages.aarch64-darwin.h3c.drvPath
```

Say in the final report that these were evaluated but not run.
