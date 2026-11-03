// xe-mtldep: latência de uma dependência entre duas filas (contextos) da GPU: A assina um MTLEvent, B espera e copia.
#import <Metal/Metal.h>
#include <stdio.h>
#include <mach/mach_time.h>
int main(int argc, char **argv) { @autoreleasepool {
    int N = argc > 1 ? atoi(argv[1]) : 60;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> qa = [d newCommandQueue], qb = [d newCommandQueue];
    id<MTLBuffer> a = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared], b = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared];
    id<MTLEvent> ev = [d newEvent];
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    double tot = 0, mx = 0, tot1 = 0;
    for (int i = 1; i <= N; i++) {
        id<MTLCommandBuffer> ca = [qa commandBuffer]; id<MTLBlitCommandEncoder> ea = [ca blitCommandEncoder]; [ea copyFromBuffer:a sourceOffset:0 toBuffer:b destinationOffset:0 size:4096]; [ea endEncoding]; [ca encodeSignalEvent:ev value:i];
        id<MTLCommandBuffer> cb = [qb commandBuffer]; [cb encodeWaitForEvent:ev value:i]; id<MTLBlitCommandEncoder> eb = [cb blitCommandEncoder]; [eb copyFromBuffer:b sourceOffset:0 toBuffer:a destinationOffset:0 size:4096]; [eb endEncoding];
        uint64_t t0 = mach_absolute_time(); [cb commit]; [ca commit]; [cb waitUntilCompleted];
        double ms = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e6; tot += ms; if (ms > mx) mx = ms;
    }
    for (int i = 0; i < N; i++) { id<MTLCommandBuffer> ca = [qa commandBuffer]; id<MTLBlitCommandEncoder> ea = [ca blitCommandEncoder]; [ea copyFromBuffer:a sourceOffset:0 toBuffer:b destinationOffset:0 size:4096]; [ea endEncoding]; uint64_t t0 = mach_absolute_time(); [ca commit]; [ca waitUntilCompleted]; tot1 += (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e6; }
    printf("%d iteracoes: com dependencia entre filas media %.2f ms maximo %.2f ms; fila unica media %.2f ms\n", N, tot / N, mx, tot1 / N);
    return 0;
} }
