{
  lib,
  stdenv,
  stdenvNoCC,
  appimageTools,
  fetchurl,
  runCommand,
  undmg,
  vulkan-loader,
  zlib,
  zstd,
}:

let
  pname = "unsloth-desktop";
  version = "0.1.804-beta";
in

if stdenvNoCC.hostPlatform.isLinux then
  let
    src = fetchurl {
      url = "https://github.com/unslothai/unsloth/releases/download/v${version}/Unsloth-Desktop-Linux.AppImage";
      hash = "sha256-LIyRALC4ybBalWDiX+IPWhuJzZp/JZeUVuQLWgmOmQg=";
    };

    appimageContents = appimageTools.extractType2 { inherit pname version src; };

    # The Python virtual environment the app builds under ~/.unsloth on first run
    # is created from a Nix-store interpreter, and the binary wheels it installs
    # there (NumPy, PyTorch, and everything downstream of them) expect the three
    # libraries below to come from the host the way they would on any ordinary
    # distribution. Nixpkgs patches glibc's loader to consult only the cache
    # inside its own store path, so neither the FHS environment's /usr/lib64 nor
    # its ld.so.conf is ever searched and LD_LIBRARY_PATH is the only way to
    # reach them.
    #
    # This is deliberately a narrow list of store paths rather than /usr/lib64:
    # the AppImage ships its own GTK, GLib, and WebKit stack, and putting the
    # whole FHS library directory ahead of those would replace the versions the
    # app was built and tested against.
    pythonWheelLibraries = lib.makeLibraryPath [
      stdenv.cc.cc.lib # Provides libstdc++.so.6 and libgcc_s.so.1.
      zlib
      zstd

      # The backend probes free VRAM for the Vulkan llama.cpp build by dlopening
      # the bundled libggml-vulkan.so from a short-lived Python subprocess, and
      # that pulls in libvulkan.so.1. The FHS environment does provide the
      # loader, but this interpreter cannot see /usr/lib64, so the probe fails
      # with "ggml-vulkan load failed" and the planner concludes the machine has
      # no GPUs at all. It then hands placement to llama.cpp's --fit at the full
      # requested context, which strands a layer on the CPU and costs roughly 3x
      # on generation. Inference itself is unaffected, since llama-server
      # resolves the loader from the FHS environment the ordinary way, so the
      # only symptom is a badly planned command line.
      vulkan-loader
    ];

    # The app's own launcher saves LD_LIBRARY_PATH into UNSLOTH_HOST_LD_LIBRARY_PATH
    # and then unsets it, so that host GTK, GLib, and WebKit libraries cannot come
    # ahead of the bundled ones. Its comment claims the value is handed back to the
    # processes it manages, but the Python backend it spawns is left with only the
    # saved copy under the other name, which nothing reads. That defeats anything
    # LD_LIBRARY_PATH is set to before launch, including the FHS environment's own
    # profile, so set the value the wheels need after the launcher has finished
    # clearing it instead. Upstream's isolation is largely preserved: libstdc++ and
    # zlib are not bundled at all, and libzstd is the only overlap, which the
    # bundled consumers reach through their own RUNPATHs anyway.
    patchedAppimageContents = runCommand "${pname}-${version}-patched" { } ''
      cp -r ${appimageContents} $out
      chmod -R u+w $out

      substituteInPlace $out/AppRun.wrapped \
        --replace-fail '# WebKitGTK resolves' 'export LD_LIBRARY_PATH="${pythonWheelLibraries}"

# WebKitGTK resolves'
    '';
  in
  appimageTools.wrapAppImage {
    inherit pname version;

    # wrapAppImage runs whatever directory it is handed here, so this is where
    # the patched copy of the extracted AppImage is substituted for the original.
    src = patchedAppimageContents;

    # The AppImage bundles a Tauri binary that dynamically loads its webview and
    # tray-icon stack from the host system rather than shipping it. None of these
    # libraries are in appimageTools' default FHS environment, so without them the
    # app exits at startup complaining about missing Linux libraries.
    extraPkgs = pkgs: [
      pkgs.webkitgtk_4_1 # Provides libwebkit2gtk-4.1 and libjavascriptcoregtk-4.1.
      pkgs.libsoup_3

      # libsoup 3 links against nghttp2 for its HTTP/2 support, but only its
      # "out" output lands in the FHS environment while the shared library
      # lives in the separate "lib" output, so it has to be requested
      # explicitly. Without it the main binary fails to start at all, since
      # libsoup is one of its direct dependencies.
      pkgs.nghttp2.lib
      pkgs.libayatana-appindicator

      # Anything that resolves libraries out of the FHS environment rather than
      # from a RUNPATH needs the C++ runtime, which appimageTools' default
      # environment does not include. The Python wheels installed under
      # ~/.unsloth get their copy from pythonWheelLibraries above instead, since
      # a Nix-store interpreter never searches /usr/lib64 at all.
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

      # The planner that builds each llama-server command line probes free VRAM
      # through nvidia-smi, then amd-smi, then torch. With amd-smi missing it
      # reaches the torch fallback, which knows only what the backend process's
      # own allocator holds, so the context size and offload split get chosen
      # against a figure that ignores any llama-server already resident on the
      # card. Installing it also drops an "amd-smi not found on PATH" warning
      # from every launch and lets the app's AMD monitoring poll real
      # utilisation figures.
      #
      # Note that this does not correct the VRAM number the UI displays. That
      # one comes from torch.cuda.memory_allocated inside the backend process,
      # which by construction cannot see a GGUF model held by a separate
      # llama.cpp process, and so reads near zero however full the card is.
      pkgs.rocmPackages.amdsmi
    ];

    # Exporting LD_LIBRARY_PATH here covers everything that runs inside the FHS
    # environment before the AppImage's own launcher takes over; the launcher
    # then clears the variable, which is why the libraries the Python backend
    # needs are re-exported from the patched AppRun.wrapped above rather than
    # from here.
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
      url = "https://github.com/unslothai/unsloth/releases/download/v${version}/Unsloth-Desktop-MacOS.dmg";
      hash = "sha256-DhzTpyQG3hYOHInIeuA8LhfBuml4dsLtUhVm+rrlJ48=";
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
