// xe-mtllong: cliente de longa duração; a cada 100 ms envia um compute trivial e mede a latência do completedHandler;
// imprime por segundo média/máximo. Serve para ver se os objetos de um cliente VIVO durante um reset ficam lentos.
#import <Metal/Metal.h>
#include <stdio.h>
#include <mach/mach_time.h>
int main(int argc, char **argv) { @autoreleasepool {
    int secs = argc > 1 ? atoi(argv[1]) : 300;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [d newCommandQueue];
    NSError *err = nil;
    id<MTLLibrary> lib = [d newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nkernel void k(device uint *p [[buffer(0)]], uint i [[thread_position_in_grid]]) { p[i] = p[i] * 3u + 1u; }" options:nil error:&err];
    id<MTLComputePipelineState> ps = [d newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k"] error:&err];
    id<MTLBuffer> a = [d newBufferWithLength:65536 options:MTLResourceStorageModeShared];
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    setvbuf(stdout, NULL, _IOLBF, 0);
    for (int s = 0; s < secs; s++) {
        __block double tot = 0, mx = 0; __block int n = 0, erros = 0;
        for (int i = 0; i < 10; i++) {
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
            [e setComputePipelineState:ps]; [e setBuffer:a offset:0 atIndex:0]; [e dispatchThreads:MTLSizeMake(16384, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)]; [e endEncoding];
            uint64_t t0 = mach_absolute_time();
            [cb addCompletedHandler:^(id<MTLCommandBuffer> c) { double ms = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e6; tot += ms; n++; if (ms > mx) mx = ms; if (c.error) erros++; dispatch_semaphore_signal(sem); }];
            [cb commit]; dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)); usleep(100000);
        }
        time_t t = time(NULL); struct tm tm; localtime_r(&t, &tm);
        printf("%02d:%02d:%02d media %.2f ms max %.2f ms n=%d erros=%d\n", tm.tm_hour, tm.tm_min, tm.tm_sec, n ? tot / n : -1, mx, n, erros);
    }
    return 0;
} }
