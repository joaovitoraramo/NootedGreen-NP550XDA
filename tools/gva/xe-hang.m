// xe-hang: provoca um reset de GPU de propósito: um kernel de compute longo demais, que estoura o limite de progresso do driver.
// Uso: xe-hang [iterações por thread]. Só para diagnóstico: a tela pode parar alguns segundos até o reset.
#import <Metal/Metal.h>
#include <stdio.h>
int main(int argc, char **argv) { @autoreleasepool {
  uint32_t iter = argc > 1 ? (uint32_t)atoi(argv[1]) : 2000000;
  id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [d newCommandQueue]; NSError *err = nil;
  id<MTLLibrary> l = [d newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nkernel void k(device uint *p [[buffer(0)]], constant uint &n [[buffer(1)]], uint i [[thread_position_in_grid]]) { uint x = i; for (uint j = 0; j < n; j++) x = x * 1664525u + 1013904223u; p[i & 0xffff] ^= x; }\n" options:nil error:&err];
  if (!l) { printf("shader: %s\n", err.localizedDescription.UTF8String); return 2; }
  id<MTLComputePipelineState> p = [d newComputePipelineStateWithFunction:[l newFunctionWithName:@"k"] error:&err]; id<MTLBuffer> b = [d newBufferWithLength:65536 * 4 options:MTLResourceStorageModePrivate];
  id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder]; [e setComputePipelineState:p]; [e setBuffer:b offset:0 atIndex:0]; [e setBytes:&iter length:4 atIndex:1];
  [e dispatchThreads:MTLSizeMake(2073600, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)]; [e endEncoding];
  CFAbsoluteTime t = CFAbsoluteTimeGetCurrent(); [cb commit]; [cb waitUntilCompleted];
  printf("terminou em %.1f s, status %ld, erro: %s\n", CFAbsoluteTimeGetCurrent() - t, (long)cb.status, cb.error ? cb.error.localizedDescription.UTF8String : "-");
  return 0;
} }
