// xe-mtlnotify: latência entre o commit e o completedHandler (aviso do kernel por porta Mach, sem polling) de um blit trivial.
#import <Metal/Metal.h>
#include <stdio.h>
#include <mach/mach_time.h>
int main(int argc, char **argv) { @autoreleasepool {
    int N = argc > 1 ? atoi(argv[1]) : 60;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [d newCommandQueue];
    id<MTLBuffer> a = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared], b = [d newBufferWithLength:4096 options:MTLResourceStorageModeShared];
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    __block double tot = 0, mx = 0; __block int n30 = 0;
    for (int i = 0; i < N; i++) {
        dispatch_semaphore_t s = dispatch_semaphore_create(0);
        id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
        [e copyFromBuffer:a sourceOffset:0 toBuffer:b destinationOffset:0 size:4096]; [e endEncoding];
        uint64_t t0 = mach_absolute_time();
        [cb addCompletedHandler:^(id<MTLCommandBuffer> c) { double ms = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e6; tot += ms; if (ms > mx) mx = ms; if (ms > 30) n30++; dispatch_semaphore_signal(s); }];
        [cb commit]; dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
        usleep(20000);
    }
    printf("%d envios: aviso de conclusao medio %.2f ms, maximo %.2f ms, acima de 30 ms: %d\n", N, tot / N, mx, n30);
    return 0;
} }
