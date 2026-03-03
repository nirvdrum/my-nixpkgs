{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  undmg,
  alsa-lib,
  at-spi2-atk,
  cairo,
  cups,
  dbus,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxcb,
  libxkbcommon,
  mesa,
  nss,
  nspr,
  pango,
  udev,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "msty-studio";
  version = "2.1.3";

  src =
    if stdenv.hostPlatform.isLinux then
      fetchurl {
        url = "https://next-assets.msty.studio/app/latest/linux/MstyStudio_amd64.deb?ver=${finalAttrs.version}";
        hash = "sha256-2f40XjbCP+b7qontA7gFLQ2H578cBz5DvJwdXfB/rn0=";
      }
    else
      fetchurl {
        url = "https://next-assets.msty.studio/app/latest/mac/MstyStudio_arm64.dmg?ver=${finalAttrs.version}";
        hash = "sha256-F4e6w0vMVpLltHi5ZyTdUlEFYadnBb28t+8t0jidqd0=";
      };

  nativeBuildInputs =
    if stdenv.hostPlatform.isLinux then
      [ dpkg autoPatchelfHook ]
    else
      [ undmg ];

  # Electron runtime dependencies needed to supplement the libraries bundled
  # inside the .deb. autoPatchelfHook resolves ELF RPATH entries against these
  # at install time, replacing references to host paths with Nix store paths.
  # On macOS the Electron .app bundle includes all required frameworks, so no
  # additional buildInputs are needed.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxcb
    libxkbcommon
    mesa
    nss
    nspr
    pango
    (lib.getLib udev)
  ];

  # Prevent Nix from trying to infer a single top-level source directory after
  # dpkg-deb (Linux) or undmg (macOS) extracts multiple top-level entries.
  sourceRoot = ".";

  unpackPhase = lib.optionalString stdenv.hostPlatform.isLinux ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase =
    if stdenv.hostPlatform.isLinux then ''
      runHook preInstall

      mkdir -p "$out/opt" "$out/bin" "$out/share"
      cp -r opt/MstyStudio "$out/opt/"
      cp -r usr/share/. "$out/share/"

      # Create a lowercase bin entry following Nix naming conventions while
      # keeping the upstream binary name intact under opt/.
      ln -s "$out/opt/MstyStudio/MstyStudio" "$out/bin/msty-studio"

      # The upstream .desktop file hard-codes /opt/MstyStudio/MstyStudio, which
      # does not exist on NixOS. Point it at the Nix store path instead.
      substituteInPlace "$out/share/applications/"*.desktop \
        --replace-fail '/opt/MstyStudio/MstyStudio' "$out/bin/msty-studio"

      runHook postInstall
    ''
    else ''
      runHook preInstall
      mkdir -p "$out/Applications"
      cp -r *.app "$out/Applications/"
      mkdir -p "$out/bin"
      ln -s "$out/Applications/MstyStudio.app/Contents/MacOS/MstyStudio" "$out/bin/msty-studio"
      runHook postInstall
    '';

  meta = {
    description = "Desktop application for running and managing local AI models";
    homepage = "https://msty.studio";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
    mainProgram = "msty-studio";
  };
})
