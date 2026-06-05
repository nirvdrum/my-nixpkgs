/*
 * Compatibility shim for building ds4 with macOS SDK < 15.0.
 *
 * Provides stub declarations for Metal types, properties, and methods
 * introduced in the macOS 15.0 SDK so the code compiles against SDK 14.4.
 * The runtime @available(macOS 15.0, *) guards in ds4_metal.m ensure these
 * stubs are never actually used at runtime on older macOS.
 */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 260000

#ifndef MTLMathModeSafe
#define MTLMathModeSafe 0
#endif

/* MTLResidencySetDescriptor was introduced in macOS 15.0 SDK. */
@interface MTLResidencySetDescriptor : NSObject
@property (copy) NSString *label;
@property (nonatomic) NSUInteger initialCapacity;
@end

/* mathMode property on MTLCompileOptions, introduced in macOS 15.0. */
@interface MTLCompileOptions (DS4MathModeCompat)
@property (nonatomic) NSInteger mathMode;
@end

/*
 * Methods introduced on MTLDevice, MTLCommandBuffer, MTLCommandQueue,
 * and MTLResidencySet in macOS 15.0.  Declaring them via an NSObject
 * category lets the compiler accept calls through both id<Protocol>
 * typed variables and plain id receivers under ARC.
 */
@interface NSObject (DS4ResidencyCompat)
- (id)newResidencySetWithDescriptor:(MTLResidencySetDescriptor *)desc error:(NSError **)error;
- (void)useResidencySet:(id)residencySet;
- (void)addResidencySet:(id)residencySet;
- (void)removeResidencySet:(id)residencySet;
- (void)addAllocation:(id)allocation;
- (void)removeAllAllocations;
- (void)requestResidency;
- (void)endResidency;
- (void)commit;
@end

#endif
