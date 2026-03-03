{
  lib,
  stdenvNoCC,
  appimageTools,
  fetchurl,
  undmg,
}:

let
  pname = "msty-studio";
  version = "2.5.4";
in

if stdenvNoCC.hostPlatform.isLinux then
  let
    src = fetchurl {
      url = "https://next-assets.msty.studio/app/latest/linux/MstyStudio_x86_64.AppImage";
      hash = "sha256-oRp6wJL6Wkh4lR0SO1MhdgfpD+DZcbLOm2ZB8BsemHg=";
    };

    appimageContents = appimageTools.extractType2 { inherit pname version src; };
  in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/MstyStudio.desktop \
        $out/share/applications/msty-studio.desktop
      substituteInPlace $out/share/applications/msty-studio.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=msty-studio'
      cp -r ${appimageContents}/usr/share/icons $out/share/
    '';

    meta = {
      description = "Desktop application for running and managing local AI models";
      homepage = "https://msty.studio";
      license = lib.licenses.unfree;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "msty-studio";
    };
  }
else
  stdenvNoCC.mkDerivation {
    inherit pname version;

    src = fetchurl {
      url = "https://next-assets.msty.studio/app/latest/mac/MstyStudio_arm64.dmg?ver=${version}";
      hash = "sha256-F4e6w0vMVpLltHi5ZyTdUlEFYadnBb28t+8t0jidqd0=";
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
      ln -s "$out/Applications/MstyStudio.app/Contents/MacOS/MstyStudio" "$out/bin/msty-studio"
      runHook postInstall
    '';

    meta = {
      description = "Desktop application for running and managing local AI models";
      homepage = "https://msty.studio";
      license = lib.licenses.unfree;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = "msty-studio";
    };
  }
