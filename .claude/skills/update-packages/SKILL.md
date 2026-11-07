---
name: update-packages
description: >
  Runs the my-nixpkgs update cycle end to end: invoke the flake's update-all app (or a single
  update-<name> app), work out which packages changed, build and actually run each one, repair
  anything the new version broke, and commit each package separately with the repo's standard
  "Update <Name> from <old> -> <new>." message. Use this whenever the user asks to update, bump,
  refresh, or check for new versions of the packages in this repo, says something like "run
  update-all", "see if there are updates", "bump everything", or "update FreeCAD", or asks to
  verify and commit the result of an update they already ran. Also use it when the user reports a
  package in this repo failing to build or start right after an update, since the fix-and-commit
  half of the workflow applies on its own.
---

# Updating packages in my-nixpkgs

The repo's `update-all` app rewrites version strings and hashes, but it cannot tell whether the result works. A green updater and a package that still launches are different things, and the gap between them is where the manual toil lives: building, launching, chasing a stale vendor hash or a renamed file, and then writing a dozen near-identical commits. This skill does that loop so the user only has to read a summary.

Work from the repo root. Keep large command output out of the conversation: send `update-all` and build logs to files in the session scratchpad and read back only the lines that matter. The examples below call that directory `$SCRATCH`; substitute the real path. Export `SMOKE_LOG_DIR` and `TMPDIR` to it as well so the helper scripts' logs land there too.

## 1. Check the starting point

Before touching anything, run `git status --short` and `git log -1 --oneline`. The commits made later should each contain exactly one package's changes, so a dirty tree would get tangled into them. Pre-existing untracked files that are unrelated to `pkgs/` (such as stray notes) are fine to leave alone; modified tracked files are not. If the tree is dirty, tell the user what is there and stop rather than guessing whether it belongs to them.

Then run `scripts/lock-info.sh`. It prints the locked nixpkgs date next to the host version and compares the glibc inside the lock with the one the host's GPU drivers use. FHS and AppImage packages load the host's Mesa inside a sandbox built from the lock's glibc, so when the lock falls behind the host, every GUI package fails at startup with GLX or EGL errors that have nothing to do with the update. Knowing the gap up front saves chasing that ghost later.

## 2. Run the updaters

```
nix run .#update-all > "$SCRATCH/update-all.log" 2>&1; echo "exit=$?"
grep -E '^=== ' "$SCRATCH/update-all.log"
```

The `===` lines say which updaters ran, succeeded, or failed. For a single package the user named, run `nix run .#update-<name>` the same way, logging to a file and checking its exit status.

A non-zero updater is not automatically a broken updater. `nix-update` writes the new version and source hash first and only then tries to compute vendor or dependency hashes by building, so a package whose new release needs a toolchain bump leaves the updater failing with the version already moved. Look at `git diff` before deciding: if the version changed, the updater did its job and the remaining failure belongs to section 4. Only when nothing moved, or the script errored on upstream's release layout (a renamed asset, a new tag scheme), does the updater script in `flake.nix` need fixing, and that gets its own commit (see section 5).

Then list what actually changed:

```
.claude/skills/update-packages/scripts/changed-packages.sh
```

It prints one line per package directory with the old and new version. Read `references/packages.md` for how each directory maps to flake attributes, its display name, and the quirks of its version string. Note that one directory can feed several attributes (`textgen` has three variants, `strix-llama-cpp` two, `godot-dev` two); every one of them needs to build.

When a changed directory has no row in that table, the package was added after the table was written. Work it out from the sources instead: the attributes come from the `callPackage ./pkgs/<dir>` lines in `flake.nix` (one directory can feed several attributes), the smoke test follows from the derivation's builder and `meta.mainProgram` (a CLI gets `--version` or `--help`, an `appimageTools` or `buildFHSEnv` package gets `smoke-gui.sh`), and the display name comes from the package's own earlier commit subjects or, failing that, the README description. Then add the row so the next run does not have to repeat the detective work; the table is part of the repo and is meant to grow with it.

If nothing changed, say so and stop. Do not create empty commits.

## 3. Build and run every changed package

For each changed attribute that builds on this machine:

```
nix build .#<attr> --no-link --print-out-paths > "$SCRATCH/build-<attr>.log" 2>&1
```

Then prove it runs, not just that it built. The reference table gives the smoke test per package, which comes down to two shapes:

- **Command-line tools and servers**: run the main program with `--version` or `--help` and confirm it exits zero. When it prints a version, compare it with the version the derivation now claims. A mismatch means the version string moved but the source did not, which has happened here when a package pins a tag literal separately from `version`.
- **Graphical applications**: use `scripts/smoke-gui.sh <attr> [seconds]`. It launches the app in its own session, waits, checks it is still alive and that stderr has no fatal-looking lines, then kills the whole process tree (plain `timeout` leaves bubblewrap children running). It prints PASS or FAIL with the evidence plus the first lines of output, where most apps print a version banner; check that banner against the new version when there is one. A PASS is evidence of surviving startup, not of a working UI, so say "launched" rather than "works" in the report.

Darwin-only packages (`h3c`, `vibe`) cannot be built on Linux. Confirm they still evaluate with `nix eval --raw .#packages.aarch64-darwin.<attr>.drvPath` and flag them as unverified in the report. The same applies in reverse on macOS for the Linux-only ones.

## 4. Fix what broke

Build failures after a version bump cluster into a few patterns. Diagnose from the log before changing anything:

- **Hash mismatch for `vendorHash`, `npmDepsHash`, or `cargoHash`**: the dependency set changed and the updater only refreshes the source hash. Copy the `got:` value from the error into the derivation. If there is no mismatch error yet because an earlier failure stopped the build before hashing, set the hash to `""` and rebuild to make Nix print the right one. Never guess a hash.
- **`go.mod requires go >= X`**: switch from `buildGoModule` to the matching `buildGo<XY>Module` (for example `buildGo127Module`), which nixpkgs ships ahead of its default. Confirm the locked nixpkgs has it first:

  ```
  nix eval --impure --raw --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux.go_1_27.version'
  ```

  Fixing the toolchain usually uncovers a vendor hash mismatch next, since the updater never got that far.
- **`install: cannot stat`** or a missing file in a post-install step: upstream renamed or removed something. List the unpacked source (`/nix/store/*-source` from the log) and point the install at the new name, or drop the step if the file is gone for good.
- **GLX, EGL, or `GLIBC_x.y not found` at launch** from an AppImage or FHS package: this is the lock drift described in step 1, not the package. Run `nix flake update nixpkgs`, rebuild, and give the lock bump its own commit placed before the package commits, since it affects every FHS package at once.
- **The updater itself failed**: fix the script in `flake.nix`, rerun that single updater, and commit the script change separately from the version bump it then produces.

After any fix, rebuild and rerun the smoke test. If a package cannot be made to work in reasonable time, leave its changes uncommitted, do not block the other packages on it, and explain the state in the report. Reverting the bump is the user's call.

## 5. Commit one package at a time

Each package gets its own commit so that `git log` and `git revert` operate per package. Stage only that package's directory (plus `README.md` if the updater changed a line for that package):

```
git add pkgs/<dir>
git commit -q -m "Update <Name> from <old> -> <new>."
```

The subject follows the repo's long-standing shape exactly, using the display name from the reference table and the version written the way earlier subjects for that package wrote it (`git log --oneline -- pkgs/<dir>` shows them). In practice that means dates with dashes and no `unstable-` prefix:

```
Update FreeCAD Weekly from 2026-10-07 -> 2026-10-28.
Update DS4 from 2026-10-07 -> 2026-11-01.
Update Godot from 4.8-beta1 to 4.8-beta2.
```

A plain bump produced by the updater is just that one line with no body and no trailer. When you had to hand-edit the derivation to make the new version work, write the message to a file and commit with `-F`: keep the same subject, add a body in complete sentences explaining what upstream changed and why the edit was needed, and end with the `Co-Authored-By` trailer for the model you are running as (the session's attribution instructions give the exact line), because that commit now contains code you wrote. Do not hard-wrap the body; the user's commit rules want paragraphs the reader's tool can soft-wrap.

Infrastructure changes (the lock bump, an updater script fix) get their own commit with a descriptive subject, committed before the package bumps that depend on them.

Never push. The user decides when the branch leaves the machine.

## 6. Report

Finish with a short table: package, old and new version, how it was verified (ran, evaluated only, or failed), and the commit hash. Below it, list anything left uncommitted and why, and any observation the user should know about even though it was not fixed (a package whose reported version disagrees with its derivation, an updater that is drifting from upstream's release layout). Keep it to what changes the user's next action.
