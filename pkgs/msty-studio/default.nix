{
  lib,
  stdenvNoCC,
  appimageTools,
  fetchurl,
  _7zz,
}:

let
  pname = "msty-studio";
  version = "2.9.0";
in

if stdenvNoCC.hostPlatform.isLinux then
  let
    src = fetchurl {
      url = "https://next-assets.msty.studio/app/latest/linux/MstyStudio_x86_64.AppImage";
      hash = "sha256-pSBrvwk4HRhcQuJD920yVbyXY3cVkLRJBtj4huqLofE=";
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
      name = "MstyStudio_arm64.dmg";
      hash = "sha256-7RJG9vhDH3b3aT2iPscB87raSOjXhi1Vy6meVym3ys0=";
    };

    nativeBuildInputs = [ _7zz ];

    # The DMG uses APFS, which undmg does not support. Use 7zz instead,
    # excluding Apple code signature extended attributes that can cause
    # the extracted app to malfunction.
    unpackPhase = ''
      runHook preUnpack
      7zz x -xr'!*.app/Contents/_CodeSignature' $src
      runHook postUnpack
    '';

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
