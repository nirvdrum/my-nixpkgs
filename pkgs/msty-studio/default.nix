{
  lib,
  stdenvNoCC,
  appimageTools,
  fetchurl,
  _7zz,
}:

let
  pname = "msty-studio";
  version = "2.9.6";
in

if stdenvNoCC.hostPlatform.isLinux then
  let
    src = fetchurl {
      url = "https://next-assets.msty.studio/app/releases/${version}/linux/MstyStudio_x86_64.AppImage";
      hash = "sha256-LNYH7fK2oaSg101Ra2dhqvDu7sPuQ0JSyqI1otnrGIE=";
    };

    appimageContents = appimageTools.extractType2 { inherit pname version src; };
  in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/mstystudio.desktop \
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
      url = "https://next-assets.msty.studio/app/releases/${version}/mac/MstyStudio_arm64.dmg";
      hash = "sha256-/RoRoeaXBvyUxpWJ/pAlzxdEk+8++RnbSkKctHwb1CE=";
    };

    nativeBuildInputs = [ _7zz ];

    # The DMG uses APFS, which undmg does not support, so use 7zz instead.
    # Extract the bundle verbatim: 7zz restores the framework symlinks that
    # Electron bundles rely on, and the code signature must be preserved
    # intact. Mach-O binaries carry their signatures embedded, while the
    # _CodeSignature directories seal the remaining resources, so omitting
    # any part of the bundle invalidates it and forces a lossy ad hoc
    # re-signing that would discard both the Developer ID signature and the
    # JIT entitlements Electron needs.
    unpackPhase = ''
      runHook preUnpack
      7zz x $src
      runHook postUnpack
    '';

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications"
      # The .app bundle is nested inside a volume-named directory (e.g. "MstyStudio
      # <version>-arm64/") rather than sitting at the top level, so a plain *.app
      # glob doesn't find it.
      app=$(find . -mindepth 1 -maxdepth 2 -name '*.app')
      cp -r "$app" "$out/Applications/"
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
