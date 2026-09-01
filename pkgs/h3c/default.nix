{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  ffmpeg,
  icu,
}:

# h3c packages antirez/h3.c (upstream project name "h3-metal"), a native
# MiniMax-H3 text-to-video/audio inference engine for Apple Silicon.
# Metal-only; there is no CPU or CUDA backend upstream.
let
  pname = "h3c";
  version = "unstable-2026-08-11";
in

if !stdenv.hostPlatform.isDarwin then
  throw "h3c currently only supports macOS (Metal backend)."
else
  stdenv.mkDerivation {
    inherit pname version;

    src = fetchFromGitHub {
      owner = "antirez";
      repo = "h3.c";
      rev = "8974cc055ea9c02fcd14cc27dfda3e1027c05153";
      hash = "sha256-Uy4wOw3WhgCSr7xEREUS4OskhhkA1a9yC75ZAjE0K5I=";
    };

    # SDK compatibility: nixpkgs ships macOS SDK 14.4, but h3.c references
    # several Metal / MetalPerformanceShadersGraph symbols introduced in
    # later SDKs (MTLCompileOptions.mathMode and MTLGPUFamilyMetal4 from
    # SDK 15.0/26.0, and MPSGraph's scaled-dot-product-attention selectors
    # from SDK 15.0). The compat headers declare stubs so the code
    # compiles; upstream's own @available and respondsToSelector: guards
    # ensure the stubs are never exercised on systems that lack the real
    # symbols.
    #
    # Separately, h3_tokenizer.m includes <unicode/uchar.h> and the
    # Makefile links against Apple's private -licucore, neither of which
    # nixpkgs' apple-sdk provides. Use nixpkgs' own icu4c instead: its
    # headers satisfy the #include, and -licuuc/-licudata provide the two
    # functions actually used (u_charType, u_isUWhiteSpace).
    postPatch = ''
      cp ${./h3c_metal_compat.h} h3c_metal_compat.h
      cp ${./h3c_mps_compat.h} h3c_mps_compat.h

      sed -i '/^#import <Metal\/Metal\.h>$/a\
#import "h3c_metal_compat.h"
' h3_metal.m h3_gpu.m

      sed -i '/^#import <MetalPerformanceShadersGraph\/MetalPerformanceShadersGraph\.h>$/a\
#import "h3c_mps_compat.h"
' h3_gpu.m

      substituteInPlace Makefile \
        --replace-fail '-licucore' '-licuuc -licudata'
    '';

    enableParallelBuilding = true;

    buildFlags = [ "h3" ];

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [ icu ];

    installPhase = ''
      runHook preInstall

      # The h3 binary loads its Metal shader source from ./h3_shaders.metal
      # at runtime, relative to the current working directory. Ship it under
      # $out/share/h3c/ and wrap the binary so it runs with that directory
      # as its working directory. ffmpeg/ffprobe are invoked by name via
      # PATH lookup for media I/O, so prepend them to the wrapper's PATH.
      install -d "$out/share/h3c"
      cp h3_shaders.metal "$out/share/h3c/"

      install -Dm755 h3 "$out/libexec/h3"
      makeWrapper "$out/libexec/h3" "$out/bin/h3" \
        --run "cd $out/share/h3c" \
        --prefix PATH : "${lib.makeBinPath [ ffmpeg ]}"

      runHook postInstall
    '';

    meta = {
      description = "MiniMax H3 text-to-video/audio inference engine for Apple Silicon (Metal)";
      homepage = "https://github.com/antirez/h3.c";
      license = lib.licenses.mit;
      platforms = lib.platforms.darwin;
      maintainers = [ ]; # add yourself if desired
      mainProgram = "h3";
    };
  }
