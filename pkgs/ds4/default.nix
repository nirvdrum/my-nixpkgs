{ lib, stdenv, fetchFromGitHub, makeWrapper }:

# DwarfStar is a native inference engine optimized for DeepSeek V4 Flash and PRO.
# Primary target is Metal on macOS; CUDA is supported on Linux but not packaged here yet.
# The CPU-only path is provided for diagnostics only and is known to crash macOS kernels.
let
  pname = "ds4";
  version = "unstable-2026-08-09";
in

if !stdenv.hostPlatform.isDarwin then
  throw "ds4 currently only supports macOS (Metal backend). CUDA support may be added in the future."
else
  stdenv.mkDerivation {
    inherit pname version;

    src = fetchFromGitHub {
      owner = "antirez";
      repo = "ds4";
      rev = "84cc882352757baf628a1776badf7cc54d584e28";
      hash = "sha256-mdvKxI+/vDQcrpHepvXPmYcTjPTRnqJWWU0UFFnLJJk=";
    };

    # Override -mcpu=native for portable binaries
    env.NATIVE_CPU_FLAG = "";

    # SDK compatibility: nixpkgs ships macOS SDK 14.4, but ds4 uses Metal
    # APIs introduced in SDK 15.0 (MTLResidencySetDescriptor,
    # MTLMathModeSafe, mathMode property). The compat header provides
    # stub declarations so the code compiles. Runtime @available checks
    # in the source ensure the stubs are never used on older macOS.
    postPatch = ''
      cp ${./ds4_metal_compat.h} ds4_metal_compat.h
      # Insert #include after the last <Metal/...> import.
      sed -i '/^#import <Metal\/Metal\.h>$/a\
#import "ds4_metal_compat.h"
' ds4_metal.m

      # Resolve MTLResidencySetDescriptor at runtime via NSClassFromString
      # to avoid linking against a class symbol that doesn't exist in SDK 14.4
      # and would conflict with the real Metal.framework class on macOS 15+.
      substituteInPlace ds4_metal.m \
        --replace-fail '[[MTLResidencySetDescriptor alloc] init]' \
                        '[NSClassFromString(@"MTLResidencySetDescriptor") new]'

      # Cast typed receivers to (id) for selectors not declared on the
      # MTLDevice / MTLCommandQueue / MTLCommandBuffer protocols in SDK 14.4.
      substituteInPlace ds4_metal.m \
        --replace-fail '[g_device newResidencySetWithDescriptor:' \
                        '[(id)g_device newResidencySetWithDescriptor:' \
        --replace-fail '[g_queue addResidencySet:' \
                        '[(id)g_queue addResidencySet:' \
        --replace-fail '[g_queue removeResidencySet:' \
                        '[(id)g_queue removeResidencySet:' \
        --replace-fail '[cb useResidencySet:' \
                        '[(id)cb useResidencySet:'
    '';

    # The Makefile sets LDLIBS with -framework via METAL_LDLIBS on Darwin;
    # the standard darwin stdenv already provides the Apple SDK with framework
    # search paths, so -framework Foundation -framework Metal resolves.
    enableParallelBuilding = true;

    installPhase = ''
      runHook preInstall

      # The ds4 binaries load Metal shader source files from ./metal/ at
      # runtime.  Ship them under $out/share/ds4/ and wrap each binary so
      # it runs with that directory as its working directory.
      install -d "$out/share/ds4/metal"
      cp metal/*.metal "$out/share/ds4/metal/"

      for binary in ds4 ds4-server ds4-bench ds4-eval ds4-agent; do
        install -Dm755 "$binary" "$out/libexec/$binary"
        makeWrapper "$out/libexec/$binary" "$out/bin/$binary" \
          --run "cd $out/share/ds4"
      done

      runHook postInstall
    '';

    nativeBuildInputs = [ makeWrapper ];

    meta = {
      description = "DeepSeek V4 Flash local inference engine for Metal and CUDA";
      homepage = "https://github.com/antirez/ds4";
      license = lib.licenses.mit;
      platforms = lib.platforms.darwin;
      maintainers = []; # add yourself if desired
      mainProgram = "ds4";
    };
  }
