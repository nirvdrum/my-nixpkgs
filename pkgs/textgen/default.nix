{
  lib,
  stdenv,
  fetchurl,
  jq,
  patchelf,

  # Linux Electron runtime dependencies
  alsa-lib,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libxcb,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libxkbcommon,
  libXrandr,
  libgbm,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
  openssl,

  # Variant selection: "cpu", "vulkan", or "rocm" (Linux x86_64 only).
  # Ignored on macOS (always uses the arm64 build).
  variant ? "cpu",
}:

let
  pname = "textgen";
  version = "4.9";

  # Map variant to the asset filename suffix.
  variantAsset = variant:
    if stdenv.hostPlatform.isDarwin then
      "macos-arm64"
    else
      "linux-${variant}";

  assetSuffix = variantAsset variant;

  # Special handling: the ROCm build has "7.2" appended to the variant name.
  fullAssetSuffix = if variant == "rocm" then "linux-rocm7.2" else assetSuffix;

  src = fetchurl {
    url = "https://github.com/oobabooga/textgen/releases/download/v${version}/textgen-portable-${version}-${fullAssetSuffix}.tar.gz";
    hash = {
      "linux-cpu" = "sha256-s4suCcnX/UsxSqr4gckuVdTWGH8agyT5hvyLc5tI76o=";
      "linux-vulkan" = "sha256-CT2zce7gYQ+7xEeZ/T8vUGtNYmYmC7UJQnGhYd+kbtk=";
      "linux-rocm" = "sha256-vKDjCRxZ3gpjooVZNUscpYmPGf0E5MiKAU+ntFeiL4I=";
      "macos-arm64" = "sha256-KUT/LDP3RJ6dfSCq5zy5zl9qfXHFtNoNpoYP/ZPNsZo=";
    }.${assetSuffix};
  };

  # Libraries that the bundled Electron binary needs at runtime.
  electronRuntimeLibs = lib.makeLibraryPath [
    alsa-lib
    atk
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libxcb
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libxkbcommon
    libXrandr
    libgbm
    mesa
    nspr
    nss
    pango
    systemd
    wayland
    openssl
    stdenv.cc.cc.lib
  ];

  # Extra library paths that the bundled llama.cpp binaries need.
  bundledLibDeps = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    openssl
  ];

  # Template for the launcher script with "STORE_APP" and "STORE_USER_DATA"
  # placeholders that get substituted with actual store paths.
  launcherTemplate = ''
    #!__SHELL__
    APP="__STORE_APP__"
    PY="$APP/portable_env/bin/python3"
    SITE_PKGS="$APP/portable_env/lib/python3.13/site-packages"
    STORE_USER_DATA="__STORE_USER_DATA__"

    # Set up a writable user-data directory outside the Nix store.
    # Seed it from the store defaults on first launch.
    DATA_DIR="$HOME/.local/share/textgen"
    for a; do
      case "$a" in
        --user-data-dir=*) DATA_DIR="''${a#--user-data-dir=}" ;;
        --user-data-dir) shift; DATA_DIR="$1" ;;
      esac
    done
    if [ ! -d "$DATA_DIR" ]; then
      mkdir -p "$DATA_DIR"
      for item in "$STORE_USER_DATA"/*; do
        [ -e "$item" ] && cp -r --no-preserve=mode "$item" "$DATA_DIR/"
      done
    fi
    # Ensure data dir is writable (store defaults are read-only).
    chmod -R u+w "$DATA_DIR"

    # Add bundled shared-library directories to the library search
    # path so that .so files inside them can find each other.
    # Covers *.libs/ (e.g., pillow.libs) and */bin/ (e.g.,
    # llama_cpp_binaries/bin).
    LIBS_DIRS=""
    for d in "$SITE_PKGS/"*.libs "$SITE_PKGS/"*/bin; do
      [ -d "$d" ] && LIBS_DIRS="''${LIBS_DIRS:+$LIBS_DIRS:}$d"
    done
    export LD_LIBRARY_PATH="''${LIBS_DIRS:+$LIBS_DIRS:}''${LD_LIBRARY_PATH:-}"

    for arg; do
        case "$arg" in
            --help|-h)
                exec "$PY" "$APP/server.py" --user-data-dir "$DATA_DIR" --help
                ;;
            --nowebui|--listen|--no-electron)
                cd "$APP" && exec "$PY" "$APP/server.py" --portable --api --user-data-dir "$DATA_DIR" "$@"
                ;;
        esac
    done
    exec "__STORE_APP__/electron/electron" --no-sandbox --no-zygote "__STORE_APP__" -- --user-data-dir "$DATA_DIR" "$@"
  '';

  launcherTemplateMacos = ''
    #!__SHELL__
    APP="__STORE_APP__"
    PY="$APP/portable_env/bin/python3"
    SITE_PKGS="$APP/portable_env/lib/python3.13/site-packages"
    STORE_USER_DATA="__STORE_USER_DATA__"

    DATA_DIR="$HOME/.local/share/textgen"
    for a; do
      case "$a" in
        --user-data-dir=*) DATA_DIR="''${a#--user-data-dir=}" ;;
        --user-data-dir) shift; DATA_DIR="$1" ;;
      esac
    done
    if [ ! -d "$DATA_DIR" ]; then
      mkdir -p "$DATA_DIR"
      for item in "$STORE_USER_DATA"/*; do
        [ -e "$item" ] && cp -r --no-preserve=mode "$item" "$DATA_DIR/"
      done
    fi
    # Ensure data dir is writable (store defaults are read-only).
    chmod -R u+w "$DATA_DIR"

    LIBS_DIRS=""
    for d in "$SITE_PKGS/"*.libs "$SITE_PKGS/"*/bin; do
      [ -d "$d" ] && LIBS_DIRS="''${LIBS_DIRS:+$LIBS_DIRS:}$d"
    done
    export LD_LIBRARY_PATH="''${LIBS_DIRS:+$LIBS_DIRS:}''${LD_LIBRARY_PATH:-}"

    for arg; do
        case "$arg" in
            --help|-h)
                exec "$PY" "$APP/server.py" --user-data-dir "$DATA_DIR" --help
                ;;
            --nowebui|--listen|--no-electron)
                cd "$APP" && exec "$PY" "$APP/server.py" --portable --api --user-data-dir "$DATA_DIR" "$@"
                ;;
        esac
    done
    exec "__STORE_APP__/electron/Electron.app/Contents/MacOS/Electron" "__STORE_APP__" -- --user-data-dir "$DATA_DIR" "$@"
  '';

in

if stdenv.hostPlatform.isLinux then

  assert lib.assertMsg (lib.elem variant [ "cpu" "vulkan" "rocm" ])
    "textgen: variant must be one of 'cpu', 'vulkan', or 'rocm', got '${variant}'";

  stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [ patchelf jq ];

    dontStrip = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -r --no-preserve=mode app "$out/"
      cp -r --no-preserve=mode user_data "$out/"

      # Restore execute permissions lost by --no-preserve=mode
      chmod -R +x "$out/app/portable_env/bin"
      for bindir in "$out/app/portable_env/lib/python3.13/site-packages/"*/bin; do
        [ -d "$bindir" ] && chmod -R +x "$bindir"
        # Create library symlinks declared in _symlinks.json (the
        # llama_cpp_binaries package would do this at runtime, but
        # the Nix store is read-only).
        symlinks_json="$bindir/_symlinks.json"
        if [ -f "$symlinks_json" ]; then
          jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$symlinks_json" |
          while IFS="$(printf '\t')" read -r name target; do
            if [ ! -e "$bindir/$name" ]; then
              ln -sf "$target" "$bindir/$name"
            fi
          done
        fi
      done
      chmod +x "$out/app/electron/electron"

      # Patch the Electron binary and its bundled .so files.
      patch_binary() {
        patchelf --set-rpath "${electronRuntimeLibs}:$out/app/electron" "$1"
      }

      patch_binary "$out/app/electron/electron"

      for lib in "$out/app/electron/"*.so*; do
        [ -f "$lib" ] && patch_binary "$lib"
      done

      # Write the launcher script with store paths substituted in.
      mkdir -p "$out/bin"
      echo '${launcherTemplate}' \
        | sed "s|__STORE_APP__|$out/app|g; s|__STORE_USER_DATA__|$out/user_data|g; s|__BUNDLED_LIB_DEPS__|${bundledLibDeps}|g; s|__SHELL__|${stdenv.shell}|g" \
        > "$out/bin/textgen"
      chmod +x "$out/bin/textgen"

      # Create desktop entry
      mkdir -p "$out/share/applications"
      cat > "$out/share/applications/textgen.desktop" << DESKTOP
    [Desktop Entry]
    Name=TextGen
    Comment=LLM inference and UI toolkit
    Exec=$out/bin/textgen
    Type=Application
    Categories=Utility;Development;AI;
    Terminal=false
    DESKTOP

      runHook postInstall
    '';

    meta = {
      description = "Local LLM inference UI supporting CPU, CUDA, ROCm, and Vulkan backends";
      homepage = "https://github.com/oobabooga/textgen";
      license = lib.licenses.agpl3Only;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "textgen";
    };
  }

else

  # macOS aarch64 build
  stdenv.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [ jq ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -r --no-preserve=mode app "$out/"
      cp -r --no-preserve=mode user_data "$out/"

      # Restore execute permissions
      chmod -R +x "$out/app/portable_env/bin"
      for bindir in "$out/app/portable_env/lib/python3.13/site-packages/"*/bin; do
        [ -d "$bindir" ] && chmod -R +x "$bindir"
        symlinks_json="$bindir/_symlinks.json"
        if [ -f "$symlinks_json" ]; then
          jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$symlinks_json" |
          while IFS="$(printf '\t')" read -r name target; do
            if [ ! -e "$bindir/$name" ]; then
              ln -sf "$target" "$bindir/$name"
            fi
          done
        fi
      done
      chmod -R +x "$out/app/electron/Electron.app/Contents/MacOS"

      # Write the launcher script with store paths substituted in.
      mkdir -p "$out/bin"
      echo '${launcherTemplateMacos}' \
        | sed "s|__STORE_APP__|$out/app|g; s|__STORE_USER_DATA__|$out/user_data|g; s|__BUNDLED_LIB_DEPS__|${bundledLibDeps}|g; s|__SHELL__|${stdenv.shell}|g" \
        > "$out/bin/textgen"
      chmod +x "$out/bin/textgen"

      runHook postInstall
    '';

    meta = {
      description = "Local LLM inference UI supporting CPU, CUDA, ROCm, and Vulkan backends";
      homepage = "https://github.com/oobabooga/textgen";
      license = lib.licenses.agpl3Only;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = "textgen";
    };
  }
