/*
 * Compatibility shim for building h3c with macOS SDK < 15.0/26.0.
 *
 * Provides stub declarations for Metal API surface introduced after the
 * macOS 14.4 SDK that nixpkgs bundles, so the code compiles. Runtime
 * @available guards in upstream ensure these stubs are never used on macOS
 * versions that lack the real symbols.
 */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 260000

/* MTLCompileOptions.mathMode, introduced in the macOS 15.0 SDK. */
#ifndef MTLMathModeSafe
#define MTLMathModeSafe 0
#endif

@interface MTLCompileOptions (H3CMathModeCompat)
@property (nonatomic) NSInteger mathMode;
@end

/* MTLGPUFamilyMetal4, introduced in the macOS 26.0 SDK. Only read behind an
 * `@available(macOS 26.0, *)` guard in h3_metal_probe(). */
#ifndef MTLGPUFamilyMetal4
#define MTLGPUFamilyMetal4 ((MTLGPUFamily)5002)
#endif

#endif
