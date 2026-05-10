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

    # The AppImage bundles libwayland-client.so which, when loaded on
    # Wayland-capable hosts, triggers EGL display creation failures
    # (EGL_BAD_PARAMETER).  Upstream PR #805 applies the same fix.
    # Removing the bundled library forces a fallback to X11 via the
    # AppImage's GTK hook (GDK_BACKEND=x11).
    appimageContents = appimageTools.extract {
      inherit pname version src;

      postExtract = ''
        rm -f $out/usr/lib/libwayland-client*
      '';
    };
  in
  appimageTools.wrapAppImage {
    inherit pname version;
    src = appimageContents;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/Whispering.desktop \
        $out/share/applications/whispering.desktop
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
