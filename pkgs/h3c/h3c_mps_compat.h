/*
 * Compatibility shim for building h3c with macOS SDK < 15.0.
 *
 * Declares the MPSGraph scaled-dot-product-attention selectors introduced
 * in the macOS 15.0 SDK so the code compiles against SDK 14.4. Call sites
 * in h3_gpu.m guard use of these selectors with a respondsToSelector:
 * check, so the stubs are never invoked on systems that lack the real
 * methods.
 */
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 260000

@interface MPSGraph (H3CAttentionCompat)
- (MPSGraphTensor *)scaledDotProductAttentionWithQueryTensor:(MPSGraphTensor *)query
                                                    keyTensor:(MPSGraphTensor *)key
                                                  valueTensor:(MPSGraphTensor *)value
                                                        scale:(float)scale
                                                         name:(NSString *)name;
- (MPSGraphTensor *)scaledDotProductAttentionWithQueryTensor:(MPSGraphTensor *)query
                                                    keyTensor:(MPSGraphTensor *)key
                                                  valueTensor:(MPSGraphTensor *)value
                                                   maskTensor:(MPSGraphTensor *)mask
                                                        scale:(float)scale
                                                         name:(NSString *)name;
@end

#endif
