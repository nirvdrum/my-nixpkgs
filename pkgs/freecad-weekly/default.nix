{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "freecad-weekly";
  version = "1.1rc3";

  src = fetchurl {
    url = "https://github.com/FreeCAD/FreeCAD/releases/download/${version}/FreeCAD_${version}-Linux-x86_64-py311.AppImage";
    hash = "sha256-QjJj1MRehKh1ajCOSpAFpvPM7/3Sw3/y9cEZntqISf0=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/org.freecad.FreeCAD.desktop -t $out/share/applications/
    substituteInPlace $out/share/applications/org.freecad.FreeCAD.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=freecad-weekly'
    cp -r ${appimageContents}/usr/share/icons $out/share/
  '';

  meta = {
    description = "General purpose Open Source 3D CAD/MCAD/CAx/CAE/PLM modeler (pre-release)";
    homepage = "https://www.freecad.org";
    license = lib.licenses.lgpl2Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "freecad-weekly";
  };
}
