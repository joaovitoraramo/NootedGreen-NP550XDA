// xe-avplay: toca uma URL/arquivo com AVPlayer (mesmo caminho de reprodução dos apps) e extrai quadros por N segundos.
// Uso: xe-avplay <url> [segundos] [largura_saida altura_saida] [janela]
#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
int main(int argc, char **argv) { @autoreleasepool {
    if (argc < 2) return 2;
    NSString *u = @(argv[1]); int secs = argc > 2 ? atoi(argv[2]) : 20, ow = argc > 4 ? atoi(argv[3]) : 0, oh = argc > 4 ? atoi(argv[4]) : 0, janela = argc > 5;
    NSURL *url = [u hasPrefix:@"http"] ? [NSURL URLWithString:u] : [NSURL fileURLWithPath:u];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    NSMutableDictionary *o = [NSMutableDictionary dictionaryWithDictionary:@{(id)kCVPixelBufferPixelFormatTypeKey: @('420v'), (id)kCVPixelBufferIOSurfacePropertiesKey: @{}}];
    if (ow) { o[(id)kCVPixelBufferWidthKey] = @(ow); o[(id)kCVPixelBufferHeightKey] = @(oh); }
    AVPlayerItemVideoOutput *vo = [[AVPlayerItemVideoOutput alloc] initWithOutputSettings:o];
    if (!janela) [item addOutput:vo];
    AVPlayer *pl = [AVPlayer playerWithPlayerItem:item]; pl.muted = YES;
    NSWindow *w = nil;
    if (janela) { [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        w = [[NSWindow alloc] initWithContentRect:NSMakeRect(40, 40, 960, 540) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO]; w.title = @"xe-avplay"; w.contentView.wantsLayer = YES;
        AVPlayerLayer *pll = [AVPlayerLayer playerLayerWithPlayer:pl]; pll.frame = w.contentView.bounds; [w.contentView.layer addSublayer:pll]; [w orderFrontRegardless]; }
    [pl play];
    int quadros = 0; NSDate *fim = [NSDate dateWithTimeIntervalSinceNow:secs]; size_t lw = 0, lh = 0; OSType lf = 0;
    while ([fim timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        if (janela) continue;
        CMTime t = [vo itemTimeForHostTime:CACurrentMediaTime()];
        if ([vo hasNewPixelBufferForItemTime:t]) { CVPixelBufferRef b = [vo copyPixelBufferForItemTime:t itemTimeForDisplay:NULL];
            if (b) { quadros++; lw = CVPixelBufferGetWidth(b); lh = CVPixelBufferGetHeight(b); lf = CVPixelBufferGetPixelFormatType(b); CVPixelBufferRelease(b); } }
    }
    NSString *cod = @"?"; for (AVPlayerItemTrack *tr in item.tracks) { for (id f in tr.assetTrack.formatDescriptions) { FourCharCode c = CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)f); if (CMFormatDescriptionGetMediaType((__bridge CMFormatDescriptionRef)f) == kCMMediaType_Video) cod = [NSString stringWithFormat:@"%c%c%c%c", c>>24, (c>>16)&255, (c>>8)&255, c&255]; } }
    AVPlayerItemAccessLogEvent *ev = item.accessLog.events.lastObject;
    printf("status=%ld erro=%s tempo=%.1f tamanho=%.0fx%.0f codec=%s quadros=%d saida=%zux%zu bitrate=%.0f descartados=%ld\n", (long)item.status, item.error ? item.error.localizedDescription.UTF8String : "-", CMTimeGetSeconds(item.currentTime), item.presentationSize.width, item.presentationSize.height, cod.UTF8String, quadros, lw, lh, ev ? ev.indicatedBitrate : 0, ev ? (long)ev.numberOfDroppedVideoFrames : 0);
    return 0;
} }
