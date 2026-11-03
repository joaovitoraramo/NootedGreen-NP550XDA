// xe-mtlrender: latência commit -> completedHandler de um kernel de COMPUTE trivial (motor de render/RCS), sem polling.
#import <Metal/Metal.h>
#include <stdio.h>
#include <mach/mach_time.h>
int main(int argc, char **argv) { @autoreleasepool {
    int N = argc > 1 ? atoi(argv[1]) : 60;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [d newCommandQueue];
    NSError *err = nil;
    id<MTLLibrary> lib = [d newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nkernel void k(device uint *p [[buffer(0)]], uint i [[thread_position_in_grid]]) { p[i] = p[i] * 3u + 1u; }" options:nil error:&err];
    if (!lib) { printf("shader: %s\n", err.localizedDescription.UTF8String); return 2; }
    id<MTLComputePipelineState> ps = [d newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k"] error:&err];
    if (!ps) { printf("pipeline: %s\n", err.localizedDescription.UTF8String); return 2; }
    id<MTLBuffer> a = [d newBufferWithLength:65536 options:MTLResourceStorageModeShared];
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    __block double tot = 0, mx = 0; __block int n30 = 0; double totw = 0;
    for (int i = 0; i < N; i++) {
        dispatch_semaphore_t s = dispatch_semaphore_create(0);
        id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
        [e setComputePipelineState:ps]; [e setBuffer:a offset:0 atIndex:0]; [e dispatchThreads:MTLSizeMake(16384, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)]; [e endEncoding];
        uint64_t t0 = mach_absolute_time();
        [cb addCompletedHandler:^(id<MTLCommandBuffer> c) { double ms = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e6; tot += ms; if (ms > mx) mx = ms; if (ms > 30) n30++; dispatch_semaphore_signal(s); }];
        [cb commit]; dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
        usleep(20000);
    }
    for (int i = 0; i < N; i++) { id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder]; [e setComputePipelineState:ps]; [e setBuffer:a offset:0 atIndex:0]; [e dispatchThreads:MTLSizeMake(16384, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)]; [e endEncoding]; uint64_t t0 = mach_absolute_time(); [cb commit]; [cb waitUntilCompleted]; totw += (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e6; }
    printf("%d envios de compute (RCS): aviso de conclusao medio %.2f ms, maximo %.2f ms, acima de 30 ms: %d; waitUntilCompleted medio %.2f ms\n", N, tot / N, mx, n30, totw / N);
    return 0;
} }
