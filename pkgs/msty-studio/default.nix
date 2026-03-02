{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
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

  src = fetchurl {
    url = "https://next-assets.msty.studio/app/latest/linux/MstyStudio_amd64.deb?ver=${finalAttrs.version}";
    hash = "sha256-2f40XjbCP+b7qontA7gFLQ2H578cBz5DvJwdXfB/rn0=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  # Electron runtime dependencies needed to supplement the libraries bundled
  # inside the .deb. autoPatchelfHook resolves ELF RPATH entries against these
  # at install time, replacing references to host paths with Nix store paths.
  buildInputs = [
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
  # dpkg-deb extracts multiple top-level directories (opt/, usr/, etc.).
  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
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
  '';

  meta = {
    description = "Desktop application for running and managing local AI models";
    homepage = "https://msty.studio";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "msty-studio";
  };
})
