{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "vibe";
  version = "2026-06-23-6bbe55d";
in

if stdenvNoCC.hostPlatform.system != "aarch64-darwin" then
  throw "vibe is only available for aarch64-darwin"
else
  stdenvNoCC.mkDerivation {
    inherit pname version;

    dontCodeSign = true;

    src = fetchurl {
      url = "https://github.com/lynaghk/vibe/releases/download/${version}/vibe-macos-arm64.zip";
      hash = "sha256-GswboZtTclXS2ZWf8mDSQQOIC5wP3+26KxnMxGdOXEQ=";
    };

    nativeBuildInputs = [ unzip ];

    sourceRoot = ".";

    unpackPhase = ''
      runHook preUnpack
      unzip -q "$src"
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      ENTITLEMENTS=$(mktemp)
      echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.virtualization</key>
	<true/>
</dict>
</plist>' > "$ENTITLEMENTS"

      /usr/bin/codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none ./vibe
      rm "$ENTITLEMENTS"

      install -Dm755 vibe "$out/bin/vibe"
      runHook postInstall
    '';

    meta = {
      description = "Easy Linux virtual machine on macOS to sandbox LLM agents";
      homepage = "https://github.com/lynaghk/vibe";
      license = lib.licenses.mit;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = "vibe";
    };
  }
