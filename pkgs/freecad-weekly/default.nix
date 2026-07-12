{
  lib,
  stdenvNoCC,
  appimageTools,
  fetchurl,
  undmg,
}:

let
  pname = "freecad-weekly";
  version = "2026.07.09";
  tag = "weekly-${version}";
in

if stdenvNoCC.hostPlatform.isLinux then
  let
    src = fetchurl {
      url = "https://github.com/FreeCAD/FreeCAD/releases/download/${tag}/FreeCAD_${tag}-Linux-x86_64.AppImage";
      hash = "sha256-RWhSY3P70m4PTYfCKFe96Vbd/R5Cnud/rudDAAyD8iY=";
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
      hash = "sha256-mGqpzuwR8zg4Sq8T4cl2eEMpiDn/4ctHbzh4gpj4Kh8=";
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
