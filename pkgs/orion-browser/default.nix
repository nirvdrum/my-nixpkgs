{
  lib,
  stdenv,
  stdenvNoCC,
  cacert,
  ostree,
  autoPatchelfHook,
  wrapGAppsHook4,
  bubblewrap,
  gtk4,
  libadwaita,
  glib,
  gst_all_1,
  libsoup_3,
  libsecret,
  icu77,
  libxml2,
  libxslt,
  harfbuzzFull,
  fontconfig,
  freetype,
  cairo,
  pango,
  gdk-pixbuf,
  graphene,
  libepoxy,
  woff2,
  libavif,
  libwebp,
  libjpeg,
  libpng,
  libjxl,
  lcms2,
  hyphen,
  enchant,
  libmanette,
  libseccomp,
  libtasn1,
  libgcrypt,
  libgpg-error,
  curl,
  openssl,
  expat,
  systemd,
  libdrm,
  libgbm,
  libGL,
  vulkan-loader,
  wayland,
  libx11,
  dbus,
  glib-networking,
  gsettings-desktop-schemas,
}:

let
  version = "0.4.1";

  # Kagi no longer publishes a versioned .flatpak bundle for each release; the
  # only distribution channel is their Flatpak repository, which is a plain
  # OSTree repository served over HTTP.  Pin the exact commit for this release
  # so the fetch stays reproducible as the `beta` ref advances.
  ostreeUrl = "https://flatpak.orionbrowser.com/repo/beta/";
  ostreeRef = "app/com.kagi.Orion/x86_64/beta";
  ostreeCommit = "34e7167b0cd363a8061593c7f097b7e611d10752274543af75c8907a67204947";

  src = stdenvNoCC.mkDerivation {
    pname = "orion-browser-source";
    inherit version;

    nativeBuildInputs = [ ostree ];

    dontUnpack = true;

    # The checkout must be a byte-for-byte copy of the upstream tree or the
    # output hash will not be stable.  In particular, the default fixup phase
    # would rewrite shebangs in the bundled helper scripts to point at the Nix
    # store, which both changes the hash and leaks a store reference into a
    # fixed-output derivation.
    dontFixup = true;

    buildPhase = ''
      runHook preBuild

      ostree --repo=repo init --mode=archive-z2

      # OSTree fetches over libcurl, which does not consult SSL_CERT_FILE, so
      # point the remote at the CA bundle explicitly.
      ostree --repo=repo remote add --no-gpg-verify \
        --set=tls-ca-path="${cacert}/etc/ssl/certs/ca-bundle.crt" \
        orion "${ostreeUrl}"

      # Requesting ref@commit pins the pull to this exact revision rather than
      # whatever the moving `beta` ref currently points at.  The output hash is
      # what actually guarantees integrity, so GPG verification is redundant.
      ostree --repo=repo pull --depth=0 orion "${ostreeRef}@${ostreeCommit}"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      ostree --repo=repo checkout --user-mode "${ostreeCommit}" "$out"

      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-vTlbxDwR0QCSXG030h1TJJU77l/KrDvcKOSBDYeq4EY=";
  };
in
stdenv.mkDerivation {
  pname = "orion-browser";

  inherit version src;

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    libadwaita
    glib
    libsoup_3
    libsecret
    icu77
    libxml2
    libxslt
    harfbuzzFull
    fontconfig
    freetype
    cairo
    pango
    gdk-pixbuf
    graphene
    libepoxy
    woff2
    libavif
    libwebp
    libjpeg
    libpng
    libjxl
    lcms2
    hyphen
    enchant
    libmanette
    libseccomp
    libtasn1
    libgcrypt
    libgpg-error
    curl
    openssl
    expat
    systemd
    libdrm
    libgbm
    libGL
    vulkan-loader
    wayland
    libx11
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
    substituteInPlace "$out/share/applications/com.kagi.Orion.desktop" \
      --replace-fail 'Exec=oriongtk' "Exec=$out/bin/oriongtk"

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
