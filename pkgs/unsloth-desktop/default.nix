{
  lib,
  stdenvNoCC,
  appimageTools,
  fetchurl,
  undmg,
}:

let
  pname = "unsloth-desktop";
  version = "0.1.800-beta";

  # Release assets encode the version with dots and hyphens both collapsed to
  # underscores (e.g. "0.1.800-beta" -> "0_1_800_beta"), while the release tag
  # keeps the original "v0.1.800-beta" form.
  urlVersion = lib.replaceStrings [ "." "-" ] [ "_" "_" ] version;
in

if stdenvNoCC.hostPlatform.isLinux then
  let
    src = fetchurl {
      url = "https://github.com/unslothai/unsloth/releases/download/v${version}/Unsloth-Desktop-${urlVersion}-Linux.AppImage";
      hash = "sha256-GpqzGpMUz0raNDcUEYZFNxe5a29SqPJ4eD0EGaq+/K0=";
    };

    appimageContents = appimageTools.extractType2 { inherit pname version src; };
  in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm444 ${appimageContents}/Unsloth.desktop \
        $out/share/applications/${pname}.desktop
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=unsloth-studio %u' 'Exec=${pname} %u'
      cp -r ${appimageContents}/usr/share/icons $out/share/
    '';

    meta = {
      description = "Native desktop app for running and training LLMs and diffusion models locally";
      homepage = "https://unsloth.ai";
      license = lib.licenses.asl20;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = pname;
    };
  }
else
  stdenvNoCC.mkDerivation {
    inherit pname version;

    # Stdenv's default Darwin fixup phase ad-hoc (re-)signs individual
    # Mach-O files it finds under $out. Disable that so our own bundle-wide
    # codesign call in postFixup below is the only signing that happens.
    dontCodeSign = true;

    src = fetchurl {
      url = "https://github.com/unslothai/unsloth/releases/download/v${version}/Unsloth-Desktop-${urlVersion}-MacOS.dmg";
      hash = "sha256-DNLyABsI34vU5H6leEzK6RRKuAFo9JZKK4nJzY4LFas=";
    };

    nativeBuildInputs = [ undmg ];

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications"
      cp -r *.app "$out/Applications/"
      mkdir -p "$out/bin"
      ln -s "$out/Applications/Unsloth.app/Contents/MacOS/unsloth-studio" "$out/bin/${pname}"
      runHook postInstall
    '';

    # Stdenv's own fixupPhase rewrites the shebang of the bundled
    # Contents/Resources/install.sh to an absolute nix store path, which
    # mutates a file the app's original Developer ID signature has already
    # sealed. Signing in installPhase would just get invalidated by that
    # later mutation, so re-sign ad hoc in postFixup instead, after every
    # other fixup step has finished touching the bundle. Ad hoc is sufficient
    # since this only needs to satisfy Gatekeeper's signature-presence check
    # for local execution, not third-party distribution.
    postFixup = ''
      /usr/bin/codesign --force --deep --sign - "$out/Applications/Unsloth.app"
    '';

    meta = {
      description = "Native desktop app for running and training LLMs and diffusion models locally";
      homepage = "https://unsloth.ai";
      license = lib.licenses.asl20;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = pname;
    };
  }
