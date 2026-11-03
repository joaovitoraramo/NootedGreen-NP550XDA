// xe-mtllat: latência entre o fim de um command buffer trivial na GPU e o aviso ao CPU (waitUntilCompleted), N vezes.
#import <Metal/Metal.h>
#include <stdio.h>
#include <mach/mach_time.h>
int main(int argc, char **argv) { @autoreleasepool {
    int N = argc > 1 ? atoi(argv[1]) : 100; int W = argc > 2 ? atoi(argv[2]) : 0;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [d newCommandQueue];
    id<MTLBuffer> a = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared], b = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared];
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    double tot = 0, mx = 0, gpu = 0; int acima = 0;
    MTLTextureDescriptor *td = W ? [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:W * 9 / 16 mipmapped:NO] : nil;
    id<MTLTexture> t1 = td ? [d newTextureWithDescriptor:td] : nil, t2 = td ? [d newTextureWithDescriptor:td] : nil;
    for (int i = 0; i < N; i++) {
        id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
        if (t1) [e copyFromTexture:t1 toTexture:t2]; else [e copyFromBuffer:a sourceOffset:0 toBuffer:b destinationOffset:0 size:4096];
        [e endEncoding];
        uint64_t t0 = mach_absolute_time(); [cb commit]; [cb waitUntilCompleted];
        double ms = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e6;
        tot += ms; if (ms > mx) mx = ms; if (ms > 20) acima++; gpu += (cb.GPUEndTime - cb.GPUStartTime) * 1000;
    }
    printf("%d envios (%s): media %.2f ms, maximo %.2f ms, acima de 20 ms: %d, tempo de GPU medio %.3f ms, GPU %s\n", N, W ? "copia de textura" : "blit 4 KB", tot / N, mx, acima, gpu / N, d.name.UTF8String);
    return 0;
} }
