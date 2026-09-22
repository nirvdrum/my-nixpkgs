{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  rocmPackages,

  # AMD GPU architecture to compile the ROCm kernels for on Linux. Upstream
  # only targets Strix Halo (Radeon 8060S), so the default is gfx1151.
  rocmArch ? "gfx1151",
}:

# DwarfStar is a native inference engine optimized for DeepSeek V4 Flash and PRO.
# On macOS it uses Metal; on Linux it uses ROCm, targeting Strix Halo systems.
# CUDA is supported upstream on Linux but is not packaged here.
# The CPU-only path is provided for diagnostics only and is known to crash macOS kernels.
let
  pname = "ds4";
  version = "unstable-2026-09-16";

  src = fetchFromGitHub {
    owner = "antirez";
    repo = "ds4";
    rev = "8db1d1d155cb0400a86a86b9c62d0defb3a6148b";
    hash = "sha256-d0TRJH5/cNlDrgJy2i9eEUuSAlnka0BvxDXlXIwMwrE=";
  };

  binaries = [ "ds4" "ds4-server" "ds4-bench" "ds4-eval" "ds4-agent" ];

  meta = {
    description = "DeepSeek V4 Flash local inference engine for Metal, CUDA, and ROCm";
    homepage = "https://github.com/antirez/ds4";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" "x86_64-linux" ];
    maintainers = []; # add yourself if desired
    mainProgram = "ds4";
  };
in

if stdenv.hostPlatform.isLinux then
  let
    rocmDeps = with rocmPackages; [
      clr
      hipblas-common
      hipblas
      hipblaslt
      rocblas
      rocwmma
      hipcub
      rocprim
    ];

    # hipcc drives ROCm's own clang rather than the nixpkgs-wrapped compiler,
    # so it does not pick up include paths, library paths, or rpath entries
    # from buildInputs. Pass them explicitly.
    rocmIncludeFlags = map (dep: "-I${lib.getDev dep}/include") rocmDeps;
    rocmLibraryPath = lib.makeLibraryPath rocmDeps;
    rocmLinkFlags = map (dep: "-L${lib.getLib dep}/lib") rocmDeps
      ++ [ "-Wl,-rpath,${rocmLibraryPath}" ];
  in
  stdenv.mkDerivation {
    inherit pname version src meta;

    nativeBuildInputs = [ rocmPackages.clr ];

    buildInputs = rocmDeps;

    # Override -march=native for portable host code. The GPU kernels are
    # still compiled for a single architecture via ROCM_ARCH.
    env.NATIVE_CPU_FLAG = "";

    # The strix-halo target re-invokes make with the ROCm object set, compiler
    # and link flags, so it is a build target rather than a set of variables.
    # ROCM_CFLAGS and ROCM_LDLIBS mirror the Makefile defaults with the nix
    # store paths appended; they are set through makeFlagsArray because their
    # values contain spaces.
    makeFlags = [
      "strix-halo"
      "HIPCC=hipcc"
      "ROCM_ARCH=${rocmArch}"
    ];

    preBuild = ''
      makeFlagsArray+=(
        "ROCM_CFLAGS=-O3 -ffast-math -g -fno-finite-math-only -pthread -D__HIP_PLATFORM_AMD__ -Wno-unused-command-line-argument --offload-arch=${rocmArch} ${lib.concatStringsSep " " rocmIncludeFlags}"
        "ROCM_LDLIBS=-lm -pthread ${lib.concatStringsSep " " rocmLinkFlags} -lhipblas -lhipblaslt -lrocblas"
      )
    '';

    enableParallelBuilding = true;

    installPhase = ''
      runHook preInstall

      for binary in ${lib.concatStringsSep " " binaries}; do
        install -Dm755 "$binary" "$out/bin/$binary"
      done

      runHook postInstall
    '';
  }
else
  stdenv.mkDerivation {
    inherit pname version src meta;

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

      for binary in ${lib.concatStringsSep " " binaries}; do
        install -Dm755 "$binary" "$out/libexec/$binary"
        makeWrapper "$out/libexec/$binary" "$out/bin/$binary" \
          --run "cd $out/share/ds4"
      done

      runHook postInstall
    '';

    nativeBuildInputs = [ makeWrapper ];
  }
