{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

# PrusaSlicer pre-release builds (alphas, betas, and release candidates).
#
# Only macOS is packaged here.  Starting with the 3.0.0 series, Prusa
# Research distributes PrusaSlicer on Linux exclusively through Flathub and
# publishes no AppImage, tarball, or other standalone Linux artifact; the
# pre-release channel lives in the separate `flathub-beta` remote.  Install it
# there with:
#
#   flatpak remote-add --if-not-exists flathub-beta https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo
#   flatpak install flathub-beta com.prusa3d.PrusaSlicer
#
# The application stores its configuration in `PrusaSlicer3-dev` rather than
# the directory used by the 2.x series, so it can be installed alongside the
# stable nixpkgs `prusa-slicer` package without the two interfering.
let
  pname = "prusa-slicer-beta";
  version = "3.0.0-alpha11";
in

if !stdenvNoCC.hostPlatform.isDarwin then
  throw "prusa-slicer-beta is only packaged for macOS; on Linux, install the pre-release from the flathub-beta remote (com.prusa3d.PrusaSlicer)"
else
  stdenvNoCC.mkDerivation {
    inherit pname version;

    src = fetchurl {
      url = "https://github.com/prusa3d/PrusaSlicer/releases/download/version_${version}/PrusaSlicer-${version}.dmg";
      hash = "sha256-6voF/eqbh/LBuNe4D3Z7hcHlhNyEAAiqW0ok+ZY/IFo=";
    };

    nativeBuildInputs = [ undmg ];

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/Applications"

      # The disk image also carries an "Applications" symlink for the
      # drag-to-install gesture.  Matching only *.app leaves it behind.
      cp -r *.app "$out/Applications/"

      # The bundle name carries the version (PrusaSlicer-3.0.0-alpha11.app),
      # which keeps concurrently installed pre-releases distinguishable in
      # Finder but means the link target cannot be hardcoded.
      mkdir -p "$out/bin"
      ln -s "$out"/Applications/*.app/Contents/MacOS/PrusaSlicer "$out/bin/${pname}"

      runHook postInstall
    '';

    meta = {
      description = "G-code generator for 3D printers, pre-release builds";
      homepage = "https://github.com/prusa3d/PrusaSlicer";
      changelog = "https://github.com/prusa3d/PrusaSlicer/releases/tag/version_${version}";
      license = lib.licenses.agpl3Plus;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = pname;
    };
  }
