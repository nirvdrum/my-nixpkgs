{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "claude-desktop";
  version = "1.5354.0";
  wrapperVersion = "2.0.8";

  src = fetchurl {
    url = "https://github.com/aaddrick/claude-desktop-debian/releases/download/v${wrapperVersion}%2Bclaude${version}/${pname}-${version}-${wrapperVersion}-amd64.AppImage";
    hash = "sha256-vli4kfOpjl7dUyLZptd+XwDjdFoJyFKq4TMIspfQD9A=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/io.github.aaddrick.claude-desktop-debian.desktop \
      $out/share/applications/${pname}.desktop
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${appimageContents}/usr/share/icons $out/share/
  '';

  meta = {
    description = "Anthropic's Claude AI desktop application for Linux (unofficial package)";
    homepage = "https://github.com/aaddrick/claude-desktop-debian";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
