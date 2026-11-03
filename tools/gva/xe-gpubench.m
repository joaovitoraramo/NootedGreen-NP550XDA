// xe-gpubench: custo real de cada operação da GPU, sem janela. Alvo e texturas de 1920x1080. Uso: xe-gpubench [passadas por teste]
// Mede: limpar, preencher, misturar, amostrar textura privada/IOSurface, YUV NV12 (como o compositor faz com vídeo), cópias e compute.
#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurface.h>
#include <stdio.h>
#include <mach/mach_time.h>
#define W 1920
#define H 1080
static id<MTLDevice> d; static id<MTLCommandQueue> q; static double tick;
static NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
 "struct V { float4 p [[position]]; float2 uv; };\n"
 "vertex V vs(uint i [[vertex_id]]) { V o; float2 t = float2((i << 1) & 2, i & 2); o.uv = t; o.p = float4(t * float2(2, -2) + float2(-1, 1), 0, 1); return o; }\n"
 "fragment float4 fsolid() { return float4(0.2, 0.4, 0.6, 0.5); }\n"
 "fragment float4 ftex(V v [[stage_in]], texture2d<float> t [[texture(0)]]) { constexpr sampler s(filter::linear); return t.sample(s, v.uv); }\n"
 "fragment float4 fnv12(V v [[stage_in]], texture2d<float> y [[texture(0)]], texture2d<float> c [[texture(1)]]) { constexpr sampler s(filter::linear);\n"
 "  float Y = y.sample(s, v.uv).r - 0.0625; float2 C = c.sample(s, v.uv).rg - 0.5;\n"
 "  return float4(1.164 * Y + 1.793 * C.y, 1.164 * Y - 0.213 * C.x - 0.533 * C.y, 1.164 * Y + 2.112 * C.x, 1); }\n"
 "kernel void k(device uint *p [[buffer(0)]], uint i [[thread_position_in_grid]]) { uint x = i; for (int n = 0; n < 64; n++) x = x * 1664525u + 1013904223u; p[i & 0xffff] ^= x; }\n";
static id<MTLRenderPipelineState> rpipe(id<MTLLibrary> l, NSString *f, BOOL blend) {
  MTLRenderPipelineDescriptor *p = [MTLRenderPipelineDescriptor new]; p.vertexFunction = [l newFunctionWithName:@"vs"]; p.fragmentFunction = [l newFunctionWithName:f];
  p.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  if (blend) { p.colorAttachments[0].blendingEnabled = YES; p.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha; p.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha; p.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne; p.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha; }
  NSError *e = nil; id<MTLRenderPipelineState> r = [d newRenderPipelineStateWithDescriptor:p error:&e]; if (!r) printf("pipeline %s: %s\n", f.UTF8String, e.localizedDescription.UTF8String); return r;
}
static CVPixelBufferRef pb(OSType f) { CVPixelBufferRef b = NULL; NSDictionary *a = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}, (id)kCVPixelBufferMetalCompatibilityKey: @YES}; CVPixelBufferCreate(NULL, W, H, f, (__bridge CFDictionaryRef)a, &b); return b; }
static void preenche(CVPixelBufferRef b) { CVPixelBufferLockBaseAddress(b, 0); size_t n = CVPixelBufferIsPlanar(b) ? CVPixelBufferGetPlaneCount(b) : 1; for (size_t pl = 0; pl < n; pl++) { uint8_t *p = CVPixelBufferIsPlanar(b) ? CVPixelBufferGetBaseAddressOfPlane(b, pl) : CVPixelBufferGetBaseAddress(b); size_t bpr = CVPixelBufferIsPlanar(b) ? CVPixelBufferGetBytesPerRowOfPlane(b, pl) : CVPixelBufferGetBytesPerRow(b), h = CVPixelBufferIsPlanar(b) ? CVPixelBufferGetHeightOfPlane(b, pl) : CVPixelBufferGetHeight(b); for (size_t y = 0; y < h; y++) for (size_t x = 0; x < bpr; x++) p[y * bpr + x] = (uint8_t)(x * 3 + y * 5); } CVPixelBufferUnlockBaseAddress(b, 0); }
static id<MTLTexture> texPlano(CVPixelBufferRef b, size_t pl, MTLPixelFormat f, size_t w, size_t h, MTLTextureUsage u) { MTLTextureDescriptor *t = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:f width:w height:h mipmapped:NO]; t.usage = u; t.storageMode = MTLStorageModeShared; return [d newTextureWithDescriptor:t iosurface:CVPixelBufferGetIOSurface(b) plane:pl]; }
typedef void (^Enc)(id<MTLCommandBuffer>);
static void mede(const char *nome, int N, double mpix, Enc enc) {
  const int porCb = 10; uint64_t t0 = mach_absolute_time(); id<MTLCommandBuffer> ult = nil; int feitos = 0; double gpu = 0;
  while (feitos < N) { id<MTLCommandBuffer> cb = [q commandBuffer]; for (int i = 0; i < porCb && feitos < N; i++, feitos++) enc(cb); [cb commit]; [cb waitUntilCompleted]; gpu += cb.GPUEndTime - cb.GPUStartTime; ult = cb; }
  double ms = (mach_absolute_time() - t0) * tick / 1e6 / N;
  printf("%-34s %8.3f ms/passada  gpu %8.3f ms  %9.0f Mpix/s%s\n", nome, ms, gpu * 1000 / N, mpix ? mpix / ms * 1000 : 0, ult.error ? "  ERRO" : ""); fflush(stdout);
}
static void quad(id<MTLCommandBuffer> cb, id<MTLTexture> alvo, MTLLoadAction load, id<MTLRenderPipelineState> p, id<MTLTexture> t0, id<MTLTexture> t1) {
  MTLRenderPassDescriptor *r = [MTLRenderPassDescriptor renderPassDescriptor]; r.colorAttachments[0].texture = alvo; r.colorAttachments[0].loadAction = load; r.colorAttachments[0].storeAction = MTLStoreActionStore; r.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.2, 0.3, 1);
  id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:r]; if (p) { [e setRenderPipelineState:p]; if (t0) [e setFragmentTexture:t0 atIndex:0]; if (t1) [e setFragmentTexture:t1 atIndex:1]; [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; } [e endEncoding];
}
int main(int argc, char **argv) { @autoreleasepool {
  int N = argc > 1 ? atoi(argv[1]) : 100; mach_timebase_info_data_t tb; mach_timebase_info(&tb); tick = (double)tb.numer / tb.denom;
  d = MTLCreateSystemDefaultDevice(); q = [d newCommandQueue]; printf("GPU: %s, alvo %dx%d, %d passadas por teste\n", d.name.UTF8String, W, H, N);
  NSError *err = nil; id<MTLLibrary> l = [d newLibraryWithSource:src options:nil error:&err]; if (!l) { printf("shader: %s\n", err.localizedDescription.UTF8String); return 2; }
  id<MTLRenderPipelineState> ps = rpipe(l, @"fsolid", NO), pb_ = rpipe(l, @"fsolid", YES), pt = rpipe(l, @"ftex", NO), pn = rpipe(l, @"fnv12", NO), pmix = rpipe(l, @"ftex", YES);
  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:H mipmapped:NO]; td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; td.storageMode = MTLStorageModePrivate;
  id<MTLTexture> aPriv = [d newTextureWithDescriptor:td], tPriv = [d newTextureWithDescriptor:td];
  CVPixelBufferRef bAlvo = pb(kCVPixelFormatType_32BGRA), bTex = pb(kCVPixelFormatType_32BGRA), bNv = pb(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
  if (!bAlvo || !bTex || !bNv) { printf("sem IOSurface\n"); return 2; } preenche(bTex); preenche(bNv);
  id<MTLTexture> aSurf = texPlano(bAlvo, 0, MTLPixelFormatBGRA8Unorm, W, H, MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead), tSurf = texPlano(bTex, 0, MTLPixelFormatBGRA8Unorm, W, H, MTLTextureUsageShaderRead), tY = texPlano(bNv, 0, MTLPixelFormatR8Unorm, W, H, MTLTextureUsageShaderRead), tC = texPlano(bNv, 1, MTLPixelFormatRG8Unorm, W / 2, H / 2, MTLTextureUsageShaderRead);
  { id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLBlitCommandEncoder> b = [cb blitCommandEncoder]; [b copyFromTexture:tSurf toTexture:tPriv]; [b endEncoding]; [cb commit]; [cb waitUntilCompleted]; }
  double M = W * H / 1e6;
  if (argc > 2) { // modo laço: mesmo teste no MESMO contexto, 1 linha por volta: mostra se um contexto vivo fica mais lento depois de um reset
    int voltas = atoi(argv[2]); for (int v = 0; v < voltas; v++) { char n[64]; snprintf(n, sizeof n, "volta %d", v); mede(n, N, M, ^(id<MTLCommandBuffer> c) { quad(c, aSurf, MTLLoadActionClear, pn, tY, tC); quad(c, aSurf, MTLLoadActionLoad, pmix, tSurf, nil); }); usleep(300000); }
    return 0;
  }
  mede("limpar, alvo privado", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aPriv, MTLLoadActionClear, nil, nil, nil); });
  mede("preencher opaco, alvo privado", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aPriv, MTLLoadActionClear, ps, nil, nil); });
  mede("preencher com mistura, privado", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aPriv, MTLLoadActionLoad, pb_, nil, nil); });
  mede("textura privada, alvo privado", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aPriv, MTLLoadActionClear, pt, tPriv, nil); });
  mede("textura IOSurface, alvo privado", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aPriv, MTLLoadActionClear, pt, tSurf, nil); });
  mede("NV12 IOSurface, alvo privado", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aPriv, MTLLoadActionClear, pn, tY, tC); });
  mede("limpar, alvo IOSurface", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aSurf, MTLLoadActionClear, nil, nil, nil); });
  mede("preencher opaco, alvo IOSurface", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aSurf, MTLLoadActionClear, ps, nil, nil); });
  mede("textura IOSurface, alvo IOSurface", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aSurf, MTLLoadActionClear, pt, tSurf, nil); });
  mede("mistura textura, alvo IOSurface", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aSurf, MTLLoadActionLoad, pmix, tSurf, nil); });
  mede("NV12 IOSurface, alvo IOSurface", N, M, ^(id<MTLCommandBuffer> c) { quad(c, aSurf, MTLLoadActionClear, pn, tY, tC); });
  mede("copia blit IOSurface -> privado", N, M, ^(id<MTLCommandBuffer> c) { id<MTLBlitCommandEncoder> b = [c blitCommandEncoder]; [b copyFromTexture:tSurf toTexture:aPriv]; [b endEncoding]; });
  mede("copia blit privado -> privado", N, M, ^(id<MTLCommandBuffer> c) { id<MTLBlitCommandEncoder> b = [c blitCommandEncoder]; [b copyFromTexture:tPriv toTexture:aPriv]; [b endEncoding]; });
  id<MTLComputePipelineState> pc = [d newComputePipelineStateWithFunction:[l newFunctionWithName:@"k"] error:&err]; id<MTLBuffer> buf = [d newBufferWithLength:65536 * 4 options:MTLResourceStorageModePrivate];
  if (pc) mede("compute, 2 Mi threads x 64 iter", N, 0, ^(id<MTLCommandBuffer> c) { id<MTLComputeCommandEncoder> e = [c computeCommandEncoder]; [e setComputePipelineState:pc]; [e setBuffer:buf offset:0 atIndex:0]; [e dispatchThreads:MTLSizeMake(2073600, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)]; [e endEncoding]; });
  return 0;
} }
