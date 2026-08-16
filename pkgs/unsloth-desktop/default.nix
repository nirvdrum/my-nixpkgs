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

    # The AppImage bundles a Tauri binary that dynamically loads its webview and
    # tray-icon stack from the host system rather than shipping it. None of these
    # libraries are in appimageTools' default FHS environment, so without them the
    # app exits at startup complaining about missing Linux libraries.
    extraPkgs = pkgs: [
      pkgs.webkitgtk_4_1 # Provides libwebkit2gtk-4.1 and libjavascriptcoregtk-4.1.
      pkgs.libsoup_3
      pkgs.libayatana-appindicator

      # On first run the app builds a Python virtual environment under
      # ~/.unsloth/studio and installs PyTorch, NumPy, and friends into it as
      # binary wheels. Those wheels link against libstdc++.so.6, which is absent
      # from appimageTools' default FHS environment, so importing torch fails
      # with an OSError. The app treats any torch import failure as "no GPU
      # backend available" and silently falls back to CPU-only mode, reporting
      # "No visible GPU detected" even when ROCm and the dGPU are working.
      pkgs.stdenv.cc.cc.lib

      # WebKitGTK and libsoup get TLS support solely from glib-networking's GIO
      # module. Without it there is no TLS backend at all, so every HTTPS request
      # the webview makes fails while plain HTTP to the local backend keeps
      # working. The visible symptom is an app that starts fine but never
      # populates the model list and returns nothing for model searches, since
      # those are fetched by the frontend directly rather than through Python.
      pkgs.glib-networking

      # glib-networking's libproxy module links against a libcurl built with
      # OpenSSL, but the only libcurl otherwise present is the GnuTLS flavour,
      # so the module fails to load with a CURL_OPENSSL_4 version error. That is
      # not fatal, since it only costs proxy autodetection rather than TLS, but
      # it puts a misleading library error on stderr on every launch.
      pkgs.curl
    ];

    # Putting libstdc++ in the FHS environment is necessary but not sufficient.
    # The virtual environment the app builds on first run is created from
    # whichever Python it finds on PATH, and inside the FHS environment that is
    # the Nix-store Python inherited from the host profile rather than an
    # FHS-native one. Nixpkgs patches the default /lib and /usr/lib entries out
    # of glibc's loader search path, so a Nix-store interpreter never looks in
    # /usr/lib64 and cannot see the FHS environment's libraries at all. Exporting
    # LD_LIBRARY_PATH is what bridges the two, since the loader honours it
    # regardless of which glibc it came from.
    #
    # GIO looks for modules in the directory compiled into the glib it was built
    # against, which is a Nix store path rather than the FHS environment's
    # /usr/lib64/gio/modules, so glib-networking would go unfound even though it
    # is installed. The host also exports GIO_EXTRA_MODULES pointing at its own
    # dconf and gvfs modules, which is inherited here, so prepend rather than
    # overwrite to leave those working.
    profile = ''
      export LD_LIBRARY_PATH="/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      export GIO_EXTRA_MODULES="/usr/lib64/gio/modules''${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}"
    '';

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
