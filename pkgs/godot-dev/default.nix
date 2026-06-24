{
  lib,
  stdenvNoCC,
  fetchurl,
  copyDesktopItems,
  makeDesktopItem,
  unzip,
  makeWrapper,
  alsa-lib,
  dbus,
  fontconfig,
  libdecor,
  libGL,
  libpulseaudio,
  libxkbcommon,
  speechd-minimal,
  udev,
  vulkan-loader,
  wayland,
  libx11,
  libxcursor,
  libxext,
  libxfixes,
  libxi,
  libxinerama,
  libxrandr,
  libxrender,
  dotnetCorePackages,
  withMono ? false,
}:

let
  pname = if withMono then "godot-dev-mono" else "godot-dev";

  # The "base version" is the upstream release cycle (e.g., "4.7") and the
  # "pre-release label" identifies the specific snapshot within that cycle
  # (e.g., "dev3", "beta1", "rc1").  Together they form the tag used by the
  # godot-builds repository on GitHub.
  baseVersion = "4.7";
  preLabel = "rc3";
  version = "${baseVersion}-${preLabel}";

  srcs = {
    linuxStandard = fetchurl {
      url = "https://github.com/godotengine/godot-builds/releases/download/${version}/Godot_v${version}_linux.x86_64.zip";
      hash = "sha256-F0ygXqkYn1J0sPP54lJgepNb/Oj/WTt1jX0RqjsEeeY=";
    };

    linuxMono = fetchurl {
      url = "https://github.com/godotengine/godot-builds/releases/download/${version}/Godot_v${version}_mono_linux_x86_64.zip";
      hash = "sha256-VIkQ7pP5K5fb6vTLVLBjLk4cNQ5Z81SU2Ahe8iFV0mo=";
    };

    macosStandard = fetchurl {
      url = "https://github.com/godotengine/godot-builds/releases/download/${version}/Godot_v${version}_macos.universal.zip";
      hash = "sha256-OmICPtO/XwZzy/niNkj0APlJOeaQRGgHXUnkXoxwUE0=";
    };

    macosMono = fetchurl {
      url = "https://github.com/godotengine/godot-builds/releases/download/${version}/Godot_v${version}_mono_macos.universal.zip";
      hash = "sha256-Z3dZvPclTYiSehU2oA+rnZw6bjBo8X4/LoMKYnLovVM=";
    };
  };

  dotnet-sdk = dotnetCorePackages.sdk_9_0;

  desktopName =
    if withMono
    then "Godot Engine ${baseVersion} Dev (Mono)"
    else "Godot Engine ${baseVersion} Dev";

  commonMeta = {
    description = "Free and open source 2D and 3D game engine (development release${lib.optionalString withMono ", with C#/.NET support"})";
    homepage = "https://godotengine.org";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = pname;
  };
in

if stdenvNoCC.hostPlatform.isDarwin then
  let
    src = if withMono then srcs.macosMono else srcs.macosStandard;

    # Both the standard and mono macOS zips ship a single universal .app
    # bundle at the archive root; only the bundle name differs.  The binary
    # inside the bundle is named "Godot" in both cases.
    appName = if withMono then "Godot_mono.app" else "Godot.app";
  in
  stdenvNoCC.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [ unzip makeWrapper ];

    sourceRoot = ".";

    installPhase =
      let
        wrapperArgs = lib.optionalString withMono
          ''--prefix PATH : "${lib.makeBinPath [ dotnet-sdk ]}"'';
      in
      ''
        runHook preInstall

        mkdir -p "$out/Applications"
        cp -r "${appName}" "$out/Applications/"

        mkdir -p "$out/bin"
        makeWrapper "$out/Applications/${appName}/Contents/MacOS/Godot" "$out/bin/${pname}" \
          ${wrapperArgs}

        runHook postInstall
      '';

    meta = commonMeta // {
      platforms = [ "aarch64-darwin" "x86_64-darwin" ];
    };
  }
else
  let
    src = if withMono then srcs.linuxMono else srcs.linuxStandard;

    binaryName =
      if withMono
      then "Godot_v${version}_mono_linux.x86_64"
      else "Godot_v${version}_linux.x86_64";

    # The pre-built binary uses dlopen (sowrap) for all external libraries, so
    # they must be available on LD_LIBRARY_PATH at runtime.
    runtimeLibs = [
      alsa-lib
      dbus.lib
      fontconfig.lib
      libdecor
      libGL
      libpulseaudio
      libxkbcommon
      speechd-minimal
      udev
      vulkan-loader
      wayland

      libx11
      libxcursor
      libxext
      libxfixes
      libxi
      libxinerama
      libxrandr
      libxrender
    ];

    runtimeLibPath = lib.makeLibraryPath runtimeLibs;

    desktopItem = makeDesktopItem {
      name = pname;
      desktopName = desktopName;
      comment = "Multi-platform 2D and 3D game engine with a feature-rich editor";
      exec = "${pname} %f";
      icon = "godot-dev";
      terminal = false;
      type = "Application";
      mimeTypes = [ "application/x-godot-project" ];
      categories = [ "Development" "IDE" ];
      startupWMClass = "Godot";
      keywords = [ "game development" "development" "IDE" "game engine" ];
    };

    icon = fetchurl {
      url = "https://godotengine.org/assets/press/icon_color.svg";
      hash = "sha256-fi8Xz0OhUeJnNkaFRAI87YwHIQxXudI4JkofGyivmGg=";
    };

  in
  stdenvNoCC.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [ copyDesktopItems unzip makeWrapper ];

    # The standard zip contains a bare binary at the top level; the mono zip
    # contains a directory.  Tell Nix not to expect a single top-level directory
    # so that both layouts extract correctly.
    sourceRoot = ".";

    installPhase =
      let
        copyBinary =
          if withMono
          then ''cp -r "Godot_v${version}_mono_linux_x86_64"/* "$out/libexec/${pname}/"''
          else ''install -m755 "${binaryName}" "$out/libexec/${pname}/"'';

        wrapperArgs = lib.concatStringsSep " " ([
          ''--prefix LD_LIBRARY_PATH : "${runtimeLibPath}"''
        ] ++ lib.optionals withMono [
          ''--prefix PATH : "${lib.makeBinPath [ dotnet-sdk ]}"''
        ]);
      in
      ''
        runHook preInstall

        mkdir -p "$out/libexec/${pname}"
        ${copyBinary}

        mkdir -p "$out/bin"
        makeWrapper "$out/libexec/${pname}/${binaryName}" "$out/bin/${pname}" \
          ${wrapperArgs}

        install -Dm444 ${icon} "$out/share/icons/hicolor/scalable/apps/godot-dev.svg"

        runHook postInstall
      '';

    desktopItems = [ desktopItem ];

    meta = commonMeta // {
      platforms = [ "x86_64-linux" ];
    };
  }
