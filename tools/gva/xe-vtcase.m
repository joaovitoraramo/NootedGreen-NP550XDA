// xe-vtcase: decodifica H.264 por hardware com uma saída escolhida e mostra se a GPU aguenta.
// Uso: xe-vtcase <nativo|420v|bgra|menor420|menorbgra|maior420|p010|menorp010> [quadros] [h264|hevc|hevc10]
#import <VideoToolbox/VideoToolbox.h>
#include <stdio.h>
#include <string.h>
static NSMutableArray *amostras;
static void enc_cb(void *r, void *s, OSStatus st, VTEncodeInfoFlags f, CMSampleBufferRef sb) { if (st == noErr && sb) [amostras addObject:(__bridge id)sb]; }
static volatile int ndec, nerr; static OSStatus lastErr; static size_t ow, oh; static OSType ofmt; static int hwUsed = -1;
static void dec_cb(void *r, void *s, OSStatus st, VTDecodeInfoFlags f, CVImageBufferRef img, CMTime pts, CMTime d) {
    if (st != noErr || !img) { nerr++; lastErr = st; return; }
    if (ndec++ == 0) { ow = CVPixelBufferGetWidth(img); oh = CVPixelBufferGetHeight(img); ofmt = CVPixelBufferGetPixelFormatType(img); }
}
int main(int argc, char **argv) { @autoreleasepool {
    const char *c = argc > 1 ? argv[1] : "nativo"; int N = argc > 2 ? atoi(argv[2]) : 60; const int W = 1280, H = 720; const char *cod = argc > 3 ? argv[3] : "h264"; int hevc = strncmp(cod, "hevc", 4) == 0, dez = !strcmp(cod, "hevc10");
    amostras = [NSMutableArray new];
    VTCompressionSessionRef e = NULL;
    OSStatus st = VTCompressionSessionCreate(NULL, W, H, hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264, (__bridge CFDictionaryRef)@{(id)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @NO}, NULL, NULL, enc_cb, NULL, &e);
    if (st) { printf("encoder erro %d\n", (int)st); return 2; }
    VTSessionSetProperty(e, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    if (dez) { VTSessionSetProperty(e, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel);
        VTSessionSetProperty(e, kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_2020);
        VTSessionSetProperty(e, kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_2100_HLG);
        VTSessionSetProperty(e, kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_2020); }
    for (int i = 0; i < N; i++) {
        CVPixelBufferRef pb; CVPixelBufferCreate(NULL, W, H, dez ? 'x420' : '420v', (__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}}, &pb);
        CVPixelBufferLockBaseAddress(pb, 0);
        uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
        size_t by = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), bc = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
        if (dez) { for (int l = 0; l < H; l++) { uint16_t *p = (uint16_t *)(y + l * by); for (int x = 0; x < W; x++) p[x] = (uint16_t)(((x + l + 4 * i) & 0x3ff) << 6); }
            for (int l = 0; l < H / 2; l++) { uint16_t *p = (uint16_t *)(uv + l * bc); for (int x = 0; x < W; x += 2) { p[x] = (uint16_t)(((x / 4 + i) & 0x3ff) << 6); p[x + 1] = (uint16_t)(((l + 512) & 0x3ff) << 6); } }
        } else { for (int l = 0; l < H; l++) for (int x = 0; x < W; x++) y[l * by + x] = (uint8_t)(x + l + 4 * i);
            for (int l = 0; l < H / 2; l++) for (int x = 0; x < W; x += 2) { uv[l * bc + x] = (uint8_t)(x / 8 + i); uv[l * bc + x + 1] = (uint8_t)(l / 4 + 128); } }
        CVPixelBufferUnlockBaseAddress(pb, 0);
        VTCompressionSessionEncodeFrame(e, pb, CMTimeMake(i, 30), kCMTimeInvalid, NULL, NULL, NULL); CVPixelBufferRelease(pb);
    }
    VTCompressionSessionCompleteFrames(e, kCMTimeInvalid);
    if (![amostras count]) { printf("nada codificado\n"); return 2; }
    NSDictionary *io = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}}; NSMutableDictionary *o = [io mutableCopy];
    if (!strcmp(c, "420v")) o[(id)kCVPixelBufferPixelFormatTypeKey] = @('420v');
    else if (!strcmp(c, "bgra")) o[(id)kCVPixelBufferPixelFormatTypeKey] = @('BGRA');
    else if (!strcmp(c, "menor420")) { o[(id)kCVPixelBufferPixelFormatTypeKey] = @('420v'); o[(id)kCVPixelBufferWidthKey] = @640; o[(id)kCVPixelBufferHeightKey] = @360; }
    else if (!strcmp(c, "menorbgra")) { o[(id)kCVPixelBufferPixelFormatTypeKey] = @('BGRA'); o[(id)kCVPixelBufferWidthKey] = @640; o[(id)kCVPixelBufferHeightKey] = @360; }
    else if (!strcmp(c, "maior420")) { o[(id)kCVPixelBufferPixelFormatTypeKey] = @('420v'); o[(id)kCVPixelBufferWidthKey] = @1920; o[(id)kCVPixelBufferHeightKey] = @1080; }
    if (!strcmp(c, "p010")) o[(id)kCVPixelBufferPixelFormatTypeKey] = @('x420');
    else if (!strcmp(c, "menorp010")) { o[(id)kCVPixelBufferPixelFormatTypeKey] = @('x420'); o[(id)kCVPixelBufferWidthKey] = @640; o[(id)kCVPixelBufferHeightKey] = @360; }
    NSDictionary *spec = @{(id)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: @YES};
    CMFormatDescriptionRef fd = CMSampleBufferGetFormatDescription((__bridge CMSampleBufferRef)amostras[0]);
    VTDecompressionOutputCallbackRecord cb = {dec_cb, NULL}; VTDecompressionSessionRef d = NULL;
    st = VTDecompressionSessionCreate(NULL, fd, (__bridge CFDictionaryRef)spec, !strcmp(c, "nativo") ? NULL : (__bridge CFDictionaryRef)o, &cb, &d);
    printf("caso %s %s: criacao=%d", cod, c, (int)st);
    if (st) { printf("\n"); return 1; }
    CFBooleanRef hw = NULL; if (!VTSessionCopyProperty(d, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &hw) && hw) hwUsed = CFBooleanGetValue(hw);
    for (id a in amostras) { VTDecodeInfoFlags inf; OSStatus s = VTDecompressionSessionDecodeFrame(d, (__bridge CMSampleBufferRef)a, 0, NULL, &inf); if (s) { nerr++; lastErr = s; } }
    VTDecompressionSessionWaitForAsynchronousFrames(d);
    printf(" hw=%d quadros=%d erros=%d ultimoErro=%d saida=%zux%zu '%c%c%c%c'\n", hwUsed, ndec, nerr, (int)lastErr, ow, oh, ofmt ? ofmt>>24 : '-', ofmt ? (ofmt>>16)&255 : '-', ofmt ? (ofmt>>8)&255 : '-', ofmt ? ofmt&255 : '-');
    VTDecompressionSessionInvalidate(d);
    return 0;
} }
