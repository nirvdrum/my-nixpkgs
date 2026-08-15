{
  lib,
  stdenvNoCC,
  appimageTools,
  fetchurl,
  undmg,
}:

let
  pname = "freecad-weekly";
  version = "2026.08.12";
  tag = "weekly-${version}";
in

if stdenvNoCC.hostPlatform.isLinux then
  let
    src = fetchurl {
      url = "https://github.com/FreeCAD/FreeCAD/releases/download/${tag}/FreeCAD_${tag}-Linux-x86_64.AppImage";
      hash = "sha256-HWtSpevexjgmPCc86mr2IZS3b4HA4uch3Tr5R+l+0Pc=";
    };

    appimageContents = appimageTools.extractType2 { inherit pname version src; };
  in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/org.freecad.FreeCAD.desktop \
        $out/share/applications/freecad-weekly.desktop
      substituteInPlace $out/share/applications/freecad-weekly.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=freecad-weekly' \
        --replace-fail 'Name=FreeCAD' 'Name=FreeCAD Weekly'
    '';

    meta = {
      description = "General purpose Open Source 3D CAD/MCAD/CAx/CAE/PLM modeler (pre-release)";
      homepage = "https://www.freecad.org";
      license = lib.licenses.lgpl2Plus;
      platforms = [ "x86_64-linux" ];
      mainProgram = "freecad-weekly";
    };
  }
else
  stdenvNoCC.mkDerivation {
    inherit pname version;

    src = fetchurl {
      url = "https://github.com/FreeCAD/FreeCAD/releases/download/${tag}/FreeCAD_${tag}-macOS15-arm64.dmg";
      hash = "sha256-F9A/+qyMluEkLLOa1FNicn0BF2saV9nI13zh+brk+WQ=";
    };

    nativeBuildInputs = [ undmg ];

    # undmg extracts the DMG contents directly into the build directory rather
    # than a named subdirectory, so we set sourceRoot to suppress Nix's
    # single-top-level-directory heuristic.
    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications"
      cp -r *.app "$out/Applications/"
      mkdir -p "$out/bin"
      ln -s "$out/Applications/FreeCAD.app/Contents/MacOS/FreeCAD" "$out/bin/freecad-weekly"
      runHook postInstall
    '';

    meta = {
      description = "General purpose Open Source 3D CAD/MCAD/CAx/CAE/PLM modeler (pre-release)";
      homepage = "https://www.freecad.org";
      license = lib.licenses.lgpl2Plus;
      platforms = [ "aarch64-darwin" ];
      mainProgram = "freecad-weekly";
    };
  }
