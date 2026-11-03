// xe-present: janela pequena com CAMetalLayer; mede quantos quadros chegam à tela por segundo e o intervalo entre eles.
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <mach/mach_time.h>
int main(int argc, char **argv) { @autoreleasepool {
    int N = argc > 1 ? atoi(argv[1]) : 180; int semVsync = argc > 2 && argv[2][0] == 'n';
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(60, 60, 320, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    w.title = @"xe-present"; w.contentView.wantsLayer = YES;
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [d newCommandQueue];
    CAMetalLayer *l = [CAMetalLayer layer]; l.device = d; l.frame = w.contentView.bounds; l.pixelFormat = MTLPixelFormatBGRA8Unorm; l.displaySyncEnabled = semVsync ? NO : YES;
    [w.contentView.layer addSublayer:l]; [w orderFrontRegardless];
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    __block int apresentados = 0; __block double ultimo = 0, maxInt = 0, somaInt = 0; __block int nInt = 0;
    uint64_t t0 = mach_absolute_time();
    for (int i = 0; i < N; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        id<CAMetalDrawable> dr = [l nextDrawable]; if (!dr) { printf("sem drawable em %d\n", i); continue; }
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor]; rp.colorAttachments[0].texture = dr.texture; rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].clearColor = MTLClearColorMake((i % 60) / 60.0, 0.2, 0.6, 1); rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp]; [e endEncoding];
        [dr addPresentedHandler:^(id<MTLDrawable> x) { double t = x.presentedTime; if (ultimo) { double it = (t - ultimo) * 1000; somaInt += it; nInt++; if (it > maxInt) maxInt = it; } ultimo = t; apresentados++; }];
        [cb presentDrawable:dr]; [cb commit];
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    double total = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e9;
    printf("%s %d quadros em %.2f s = %.1f fps; apresentados %d; intervalo medio %.1f ms, maximo %.1f ms\n", semVsync ? "sem-vsync" : "vsync", N, total, N / total, apresentados, nInt ? somaInt / nInt : 0, maxInt);
    return 0;
} }
