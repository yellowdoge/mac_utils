//
// clang++ vt_decompression_session_create.mm -framework CoreMedia -framework VideoToolbox -framework AppKit -o vt_decompression_session_create
//

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

CMVideoCodecType codecs[]= {
kCMVideoCodecType_Animation        ,
kCMVideoCodecType_Cinepak          ,
kCMVideoCodecType_JPEG             ,
kCMVideoCodecType_JPEG_OpenDML     ,
kCMVideoCodecType_SorensonVideo    ,
kCMVideoCodecType_SorensonVideo3   ,
kCMVideoCodecType_H263             ,
kCMVideoCodecType_H264             ,
kCMVideoCodecType_MPEG4Video       ,
kCMVideoCodecType_MPEG2Video       ,
kCMVideoCodecType_MPEG1Video       ,
kCMVideoCodecType_DVCNTSC          ,
kCMVideoCodecType_DVCPAL           ,
kCMVideoCodecType_DVCProPAL        ,
kCMVideoCodecType_DVCPro50NTSC     ,
kCMVideoCodecType_DVCPro50PAL      ,
kCMVideoCodecType_DVCPROHD720p60   ,
kCMVideoCodecType_DVCPROHD720p50   ,
kCMVideoCodecType_DVCPROHD1080i60  ,
kCMVideoCodecType_DVCPROHD1080i50  ,
kCMVideoCodecType_DVCPROHD1080p30  ,
kCMVideoCodecType_DVCPROHD1080p25  ,
kCMVideoCodecType_AppleProRes4444  ,
kCMVideoCodecType_AppleProRes422HQ ,
kCMVideoCodecType_AppleProRes422   ,
kCMVideoCodecType_AppleProRes422LT ,
kCMVideoCodecType_AppleProRes422Proxy,
};

#define FourCC2Str(code) (char[5]){(code >> 24) & 0xFF, (code >> 16) & 0xFF, (code >> 8) & 0xFF, code & 0xFF, 0}

int main() {

  CFMutableDictionaryRef hardware_deco_need =
     CFDictionaryCreateMutable(kCFAllocatorDefault,
                               1,  // capacity
                               &kCFTypeDictionaryKeyCallBacks, 
                               &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(
      hardware_deco_need,
      kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder,
      kCFBooleanFalse);

  for (const auto& codec : codecs) {
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

    {
      VTDecompressionOutputCallbackRecord callback = {0};
      VTDecompressionSessionRef session;
      OSStatus status2 = VTDecompressionSessionCreate(
        kCFAllocatorDefault,
        format_description /* videoFormatDescription */,
        NULL /* videoDecoderSpecification */,
        NULL /* destinationImageBufferAttributes */,
        &callback,
        &session);
  
      if (status2) {
        NSLog(@"%s: Error creating DecompressionSession\n", FourCC2Str(codec));
        continue;
      } else {
        NSLog(@"%s: DecompressionSession created OK\n", FourCC2Str(codec));
      }
      VTDecompressionSessionInvalidate(session);
    }

    {
      VTDecompressionOutputCallbackRecord callback = {0};
      VTDecompressionSessionRef session;
      OSStatus status2 = VTDecompressionSessionCreate(
        kCFAllocatorDefault,
        format_description /* videoFormatDescription */,
        hardware_deco_need /* videoDecoderSpecification */,
        NULL /* destinationImageBufferAttributes */,
        &callback,
        &session);
  
      if (status2)
        NSLog(@"%s: Error creating DecompressionSession with required Hw Accel\n", FourCC2Str(codec));
      else
        NSLog(@"%s: DecompressionSession with Hw Accel created OK\n", FourCC2Str(codec));

      VTDecompressionSessionInvalidate(session);
    }
  }
}
