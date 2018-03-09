//
// clang++ vt_decompression_session_create.mm -framework CoreMedia -framework VideoToolbox -framework AppKit -o vt_decompression_session_create
//

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

const CMVideoCodecType codecs[] = {
    kCMVideoCodecType_Animation,
    kCMVideoCodecType_Cinepak,
    kCMVideoCodecType_JPEG,
    kCMVideoCodecType_JPEG_OpenDML,
    kCMVideoCodecType_SorensonVideo,
    kCMVideoCodecType_SorensonVideo3,
    kCMVideoCodecType_H263,
    kCMVideoCodecType_H264,
    kCMVideoCodecType_HEVC,  // Added in MacOSX10.12.sdk
    kCMVideoCodecType_MPEG4Video,
    kCMVideoCodecType_MPEG2Video,
    kCMVideoCodecType_MPEG1Video,
    kCMVideoCodecType_DVCNTSC,
    kCMVideoCodecType_DVCPAL,
    kCMVideoCodecType_DVCProPAL,
    kCMVideoCodecType_DVCPro50NTSC,
    kCMVideoCodecType_DVCPro50PAL,
    kCMVideoCodecType_DVCPROHD720p60,
    kCMVideoCodecType_DVCPROHD720p50,
    kCMVideoCodecType_DVCPROHD1080i60,
    kCMVideoCodecType_DVCPROHD1080i50,
    kCMVideoCodecType_DVCPROHD1080p30,
    kCMVideoCodecType_DVCPROHD1080p25,
    kCMVideoCodecType_AppleProRes4444,
    kCMVideoCodecType_AppleProRes422HQ,
    kCMVideoCodecType_AppleProRes422,
    kCMVideoCodecType_AppleProRes422LT,
    kCMVideoCodecType_AppleProRes422Proxy,
};

#define FourCC2Str(code)                                                       \
  (char[5]) {                                                                  \
    (code >> 24) & 0xFF, (code >> 16) & 0xFF, (code >> 8) & 0xFF, code & 0xFF, \
        0                                                                      \
  }

int main() {

  // |hardware_deco_needed| is a dictionary of options to force hardware
  // acceleration or die.
  CFMutableDictionaryRef hardware_deco_needed = CFDictionaryCreateMutable(
      kCFAllocatorDefault,
      1, // capacity
      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(
      hardware_deco_needed,
      kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder,
      kCFBooleanFalse);

  for (const auto &codec : codecs) {
    CFDictionaryRef extensions;
    CMFormatDescriptionRef format_description;
    OSStatus status1 = CMVideoFormatDescriptionCreate(
        kCFAllocatorDefault,
        codec,
        640, 480,
        extensions,
        &format_description);
    if (status1) {
      NSLog(@"%s: Error creating FormatDescription\n", FourCC2Str(codec));
      continue;
    }

    // Try first without acceleration, bail if that doesn't work.
    static const bool accelerations[] = {false, true};
    for (const bool acceleration : accelerations) {
      VTDecompressionOutputCallbackRecord callback = {0};
      VTDecompressionSessionRef session;
      OSStatus status2 = VTDecompressionSessionCreate(
          kCFAllocatorDefault,
          format_description /* videoFormatDescription */,
          acceleration ? hardware_deco_needed : NULL,
          NULL /* destinationImageBufferAttributes */,
          &callback,
          &session);

      if (status2) {
        NSLog(@"%s: Error creating VTDecompressionSession %s acceleration\n",
              FourCC2Str(codec), (acceleration ? "WITH" : "WITHOUT"));
        break;
      } else {
        NSLog(@"%s: VTDecompressionSession %s acceleration OK\n",
              FourCC2Str(codec), (acceleration ? "WITH" : "WITHOUT"));
      }
      VTDecompressionSessionInvalidate(session);
      CFRelease(session);
    }
  }

  CFRelease(hardware_deco_needed);
}
