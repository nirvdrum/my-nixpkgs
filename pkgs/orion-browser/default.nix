{
  lib,
  stdenv,
  fetchurl,
  flatpak,
  ostree,
  autoPatchelfHook,
  wrapGAppsHook4,
  bubblewrap,
  gtk4,
  libadwaita,
  webkitgtk_6_0,
  glib,
  gst_all_1,
  libsoup_3,
  json-glib,
  libsecret,
  sqlite,
  icu77,
  libxml2,
  harfbuzz,
  fontconfig,
  freetype,
  cairo,
  pango,
  gdk-pixbuf,
  librsvg,
  mesa,
  libGL,
  vulkan-loader,
  wayland,
  libxkbcommon,
  dbus,
  glib-networking,
  gsettings-desktop-schemas,
}:

stdenv.mkDerivation {
  pname = "orion-browser";

  # The upstream Flatpak bundle has no formal version; the filename
  # contains "earlybeta.1" and the bundle was last updated on 2026-03-17.
  version = "0-unstable-2026-03-17";

  src = fetchurl {
    url = "https://cdn.kagi.com/downloads/oriongtk.earlybeta.1.flatpak";
    hash = "sha256-bX2k0SPyPuaGhYBKJfEn/QnIK2BLBfDjaku8eGfQ+Z4=";
  };

  nativeBuildInputs = [
    flatpak
    ostree
    autoPatchelfHook
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    libadwaita
    webkitgtk_6_0
    glib
    libsoup_3
    json-glib
    libsecret
    sqlite
    icu77
    libxml2
    harfbuzz
    fontconfig
    freetype
    cairo
    pango
    gdk-pixbuf
    librsvg
    mesa
    libGL
    vulkan-loader
    wayland
    libxkbcommon
    dbus
    glib-networking
    gsettings-desktop-schemas

    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
  ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack

    # Extract the Flatpak bundle by importing it into a temporary OSTree
    # repository and then checking out the application commit.
    mkdir repo
    ostree --repo=repo init --mode=bare-user-only
    flatpak build-import-bundle repo "$src"
    ostree --repo=repo checkout --user-mode app/com.kagi.OrionGtk/x86_64/master source

    runHook postUnpack
  '';

  sourceRoot = "source";

  installPhase = ''
    runHook preInstall

    # The Flatpak checkout contains files/ (application content) and
    # export/ (desktop integration files such as icons and .desktop entries).
    mkdir -p "$out"
    cp -r files/* "$out/"

    if [ -d export/share ]; then
      cp -r export/share/* "$out/share/"
    fi

    # Point the desktop file at the wrapped binary in the Nix store.
    if [ -f "$out/share/applications/com.kagi.OrionGtk.desktop" ]; then
      substituteInPlace "$out/share/applications/com.kagi.OrionGtk.desktop" \
        --replace-fail 'Exec=oriongtk' "Exec=$out/bin/oriongtk"
    fi

    runHook postInstall
  '';

  # The bundled WebKitGTK has /app/libexec/webkitgtk-6.0/ hardcoded as the
  # path for its helper processes (WebKitNetworkProcess, WebKitWebProcess,
  # etc.).  This is the standard Flatpak app prefix and cannot be overridden
  # with an environment variable.  We use bubblewrap to bind-mount $out at
  # /app inside a lightweight mount namespace so the hardcoded paths resolve
  # correctly, mirroring what Flatpak itself does at runtime.
  postFixup = ''
    # wrapGAppsHook4 already created a wrapper at oriongtk (setting
    # GSettings schemas, GIO modules, etc.).  Rename it so we can put
    # the bubblewrap wrapper in its place.
    mv "$out/bin/oriongtk" "$out/bin/.oriongtk-gapps"

    cat > "$out/bin/oriongtk" <<'WRAPPER'
#!/bin/sh
exec @bwrap@ \
  --tmpfs / \
  --ro-bind /nix /nix \
  --ro-bind /etc /etc \
  --bind /run /run \
  --bind /tmp /tmp \
  --bind "$HOME" "$HOME" \
  --dev-bind /dev /dev \
  --proc /proc \
  --ro-bind /sys /sys \
  --ro-bind @bwrap@ /usr/bin/bwrap \
  --ro-bind @out@ /app \
  --setenv WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS 1 \
  --die-with-parent \
  @out@/bin/.oriongtk-gapps "$@"
WRAPPER

    substituteInPlace "$out/bin/oriongtk" \
      --replace-fail '@bwrap@' '${lib.getExe bubblewrap}' \
      --replace-fail '@out@' "$out"
    chmod +x "$out/bin/oriongtk"
  '';

  meta = {
    description = "Web browser built by Kagi, using WebKitGTK";
    homepage = "https://orionbrowser.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "oriongtk";
  };
}
