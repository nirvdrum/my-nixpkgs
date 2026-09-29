{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchNpmDeps,
  cmake,
  installShellFiles,
  makeWrapper,
  ninja,
  nodejs_latest,
  npmHooks,
  openssl,
  pkg-config,

  # Vulkan backend.
  shaderc,
  spirv-headers,
  vulkan-headers,
  vulkan-loader,

  # ROCm/HIP backend.
  rocmPackages,

  # Which GPU backend to build: "vulkan" (RADV, the fork's default
  # recommendation for Strix Halo) or "rocm".
  variant ? "vulkan",

  # AMD GPU architectures to compile the HIP kernels for. The fork's
  # optimizations target Strix Halo (Radeon 8060S), so the default is gfx1151
  # alone, which also keeps the HIP build to a fraction of the time an
  # all-architecture build takes.
  rocmGpuTargets ? [ "gfx1151" ],
}:

# A llama.cpp fork tuned for AMD Strix Halo (gfx1151): Vulkan fixes for RDNA
# 3.5, HIP matmul, MoE, and flash-attention kernels, and model support (such as
# Qwen3.8 Flash Next's sparse attention) ahead of mainline. The fork has no
# release tarballs and its tags lag the optimization work by weeks, so this
# tracks the head of master.
#
# This is deliberately a standalone derivation rather than an override of
# nixpkgs' llama-cpp. The consuming configuration substitutes its own nixpkgs
# for the one pinned here, and the structure of the llama-cpp recipe differs
# enough between those revisions (how the build number is derived, which
# attributes exist) that an override would build differently in each.

assert lib.assertOneOf "variant" variant [
  "vulkan"
  "rocm"
];

let
  vulkanSupport = variant == "vulkan";
  rocmSupport = variant == "rocm";

  # llama.cpp stamps these into `llama-server --version`, `/props`, and the
  # web UI. Upstream derives them from git history, which a GitHub archive
  # does not carry, so the update script records the commit count here. They
  # are informational only; nothing gates on them.
  buildNumber = "11223";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "strix-llama-cpp-${variant}";
  version = "unstable-2026-09-26";

  __structuredAttrs = true;
  strictDeps = true;

  outputs = [
    "out"
    "dev"
  ];

  src = fetchFromGitHub {
    owner = "halo-box";
    repo = "strix-llama.cpp";
    rev = "52d7e100b6de1f282faa2054cf1f955e4d442e90";
    hash = "sha256-1hEwhx/EVMTQm9hyfKf/+dQBN/TzKh21LxdcsfF4viQ=";
  };

  # The web UI served by llama-server is a Svelte app that is compiled during
  # the build and embedded into the binary.
  npmRoot = "tools/ui";
  npmDepsHash = "sha256-2Q7XhaLAArmviOLdQsNbYTfdyDE5pW9lR26cRHEVl9k=";
  npmDeps = fetchNpmDeps {
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    inherit (finalAttrs) src;
    sourceRoot = "${finalAttrs.src.name}/${finalAttrs.npmRoot}";
    hash = finalAttrs.npmDepsHash;
  };

  nativeBuildInputs = [
    cmake
    installShellFiles
    ninja
    nodejs_latest
    npmHooks.npmConfigHook
    pkg-config
  ]
  # glslc compiles the Vulkan shaders at build time.
  ++ lib.optionals vulkanSupport [ shaderc ]
  ++ lib.optionals rocmSupport [ makeWrapper ];

  buildInputs = [
    openssl
  ]
  ++ lib.optionals vulkanSupport [
    spirv-headers
    vulkan-headers
    vulkan-loader
  ]
  ++ lib.optionals rocmSupport (
    with rocmPackages;
    [
      clr
      hipblas
      rocblas
    ]
  );

  preConfigure = ''
    pushd ${finalAttrs.npmRoot}
    LLAMA_BUILD_NUMBER=${buildNumber} npm run build
    popd
  '';

  cmakeFlags = [
    # -march=native would make the build depend on the builder's CPU.
    (lib.cmakeBool "GGML_NATIVE" false)
    (lib.cmakeBool "LLAMA_BUILD_EXAMPLES" false)
    (lib.cmakeBool "LLAMA_BUILD_SERVER" true)
    (lib.cmakeBool "LLAMA_BUILD_TESTS" false)
    (lib.cmakeBool "LLAMA_BUILD_IS_DEV" false)
    (lib.cmakeBool "LLAMA_OPENSSL" true)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "GGML_BLAS" false)
    (lib.cmakeBool "GGML_HIP" rocmSupport)
    (lib.cmakeBool "GGML_VULKAN" vulkanSupport)
    (lib.cmakeFeature "LLAMA_BUILD_NUMBER" buildNumber)
    (lib.cmakeFeature "LLAMA_BUILD_COMMIT" (builtins.substring 0 7 finalAttrs.src.rev))

    # Build every CPU backend variant and pick one at runtime. Layers that
    # spill onto the CPU then use the Zen 5 cores' AVX-512 rather than the
    # baseline x86-64 instruction set, without tying the build to one CPU.
    # The backends are loadable modules placed next to the executables in
    # bin/, which is also where Unsloth Studio looks for a GPU backend when
    # deciding whether a llama.cpp directory is GPU-capable.
    (lib.cmakeBool "GGML_CPU_ALL_VARIANTS" true)
    (lib.cmakeBool "GGML_BACKEND_DL" true)
  ]
  ++ lib.optionals rocmSupport [
    (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.clr.hipClangPath}/clang++")
    (lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" (lib.concatStringsSep ";" rocmGpuTargets))
  ];

  postInstall = ''
    installShellCompletion --cmd llama-server --bash <($out/bin/llama-server --completion-bash)
  '';

  # The fork's HIP path has an asynchronous-execution correctness problem on
  # gfx1151 that its own CI works around by serializing kernel launches. The
  # README calls it a ROCm/HIP issue rather than a llama.cpp one, so default
  # the workaround on for every executable while still letting a caller
  # override it.
  postFixup = lib.optionalString rocmSupport ''
    for program in $out/bin/llama*; do
      if [ -f "$program" ] && [ -x "$program" ]; then
        wrapProgram "$program" --set-default HIP_LAUNCH_BLOCKING 1
      fi
    done
  '';

  # Upstream's test suite needs network access and GPU hardware.
  doCheck = false;

  meta = {
    description =
      "Fork of llama.cpp optimized for AMD Strix Halo"
      + lib.optionalString vulkanSupport ", with Vulkan support"
      + lib.optionalString rocmSupport ", with ROCm support";
    homepage = "https://github.com/halo-box/strix-llama.cpp";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    mainProgram = "llama-server";
  };
})
