{
  lib,
  stdenvNoCC,
  appimageTools,
  fetchurl,
}:

let
  pname = "whispering";
  version = "7.11.0";
in

if stdenvNoCC.hostPlatform.isLinux then
  let
    src = fetchurl {
      url = "https://github.com/EpicenterHQ/epicenter/releases/download/v${version}/Whispering_${version}_amd64.AppImage";
      hash = "sha256-Yxf6jvouW2TOeegtWMMO0TAGGIqv0MES8C81wAsnqBU=";
    };

    appimageContents = appimageTools.extractType2 { inherit pname version src; };
  in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/Whispering.desktop \
        $out/share/applications/whispering.desktop
      substituteInPlace $out/share/applications/whispering.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=whispering'
      cp -r ${appimageContents}/usr/share/icons $out/share/
    '';

    meta = {
      description = "Press shortcut, speak, get text: open-source local-first transcription with optional AI transformations";
      homepage = "https://whispering.epicenterhq.com";
      license = lib.licenses.agpl3Only;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "whispering";
    };
  }
else
  stdenvNoCC.mkDerivation {
    inherit pname version;

    src = fetchurl {
      url = "https://github.com/EpicenterHQ/epicenter/releases/download/v${version}/Whispering_aarch64.app.tar.gz";
      hash = "sha256-isU2UhjRhy/yAg1jLmwjiZFmHSfDUzAlojaxo97g5KE=";
    };

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications"
      cp -r Whispering.app "$out/Applications/"
      mkdir -p "$out/bin"
      ln -s "$out/Applications/Whispering.app/Contents/MacOS/whispering" "$out/bin/whispering"
      runHook postInstall
    '';

    meta = {
      description = "Press shortcut, speak, get text: open-source local-first transcription with optional AI transformations";
      homepage = "https://whispering.epicenterhq.com";
      license = lib.licenses.agpl3Only;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = "whispering";
    };
  }
