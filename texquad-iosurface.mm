// Compile with:
// clang++ texquad-iosurface.mm -framework AppKit -framework OpenGL -framework IOSurface -framework CoreVideo -framework QuartzCore -o texquad-iosurface
//
#import  <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <OpenGL/OpenGL.h>
#include <OpenGL/GLU.h>
#include <OpenGL/GLext.h>

//#include "texquad.cc"

@interface CALayer (Private)
- (void)setContentsChanged;
@end

@interface MainView : NSView
- (void)displayLinkCallback;
@end

void* io_surface_base_addr = NULL;
CGLContextObj cgl_context = NULL;
CGLPixelFormatObj cgl_pixel_format = NULL;
GLuint gl_texture = 0;
GLuint gl_fbo = 0;
CGContextRef cg_context = NULL;
CGImageRef cg_image = NULL;
IOSurfaceRef io_surface = NULL;

const float scale_factor = 2;
const int width = 1000;
const int height = 640;
const int px_width = 2000;
const int px_height = 1280;

MainView* main_view = nil;
CALayer* main_layer = nil;
CVDisplayLinkRef g_display_link = NULL;

static CVReturn
DisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now,
                    const CVTimeStamp *outputTime, CVOptionFlags flagsIn,
                    CVOptionFlags *flagsOut, void *displayLinkContext) {
  [main_view performSelectorOnMainThread:@selector(displayLinkCallback)
                            withObject:nil
                         waitUntilDone:NO];
  return kCVReturnSuccess;
}

void DisplayLinkInit() {
  CVDisplayLinkCreateWithActiveCGDisplays(&g_display_link);
  CVDisplayLinkSetOutputCallback(g_display_link, &DisplayLinkCallback, NULL);
  CVDisplayLinkStart(g_display_link);
}

@implementation MainView

- (void)displayLinkCallback {
  [self performSelector:@selector(updateFrame) withObject:nil afterDelay:0.5/60.];
}

- (void)updateFrame {
  CGLSetCurrentContext(cgl_context);
  //TexQuadInit();
  //MakeBufferCurrent();
  //DrawTiles();
  glBindFramebuffer(GL_FRAMEBUFFER, gl_fbo);

  CFAbsoluteTime timeInSeconds = CFAbsoluteTimeGetCurrent();
  double green = fmod(timeInSeconds, 25.0) / 25.0;
  double red = fmod(timeInSeconds, 10.0) / 10.0;
  glClearColor(red, green, 0.675f, 1.0f);
  printf("R:%.3f G:%.3f\n", red, green);
  glClear(GL_COLOR_BUFFER_BIT);

  //DrawBuffer();
  glFlush();
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  CGLSetCurrentContext(NULL);

  [main_layer setContentsChanged];
}

@end

int main(int argc, char* argv[]) {
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  NSMenu* menubar = [NSMenu alloc];
  [NSApp setMainMenu:menubar];

  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 1000, 640)
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:NO];
  NSView* view = [window contentView];
  [window setFrameOrigin:NSMakePoint(20, 20)];
  [window setTitle:@"Textured Quad with CALayer and CGImage"];
  [window makeKeyAndOrderFront:nil];

  NSOpenGLPixelFormatAttribute pixelFormatAttributes[] = {
      NSOpenGLPFAColorSize, 24, NSOpenGLPFAAlphaSize, 8, NSOpenGLPFAAccelerated, 0
  };
  NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc]
      initWithAttributes:pixelFormatAttributes];
  main_view = [[MainView alloc]
      initWithFrame:[view bounds]];

  [view setWantsLayer:YES];

  main_layer = [[CALayer alloc] init];
  [main_layer setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
  [main_layer setFrame:CGRectMake(0, 0, 1000, 640)];
  [[view layer] addSublayer:main_layer];

  // Create an IOSurface.
  {
    unsigned pixelFormat = 'R10k'; //'BGRA'; // 'R10k';
    unsigned bytesPerElement = 4;

    size_t bytesPerRow = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, px_width * bytesPerElement);
    size_t totalBytes = IOSurfaceAlignProperty(kIOSurfaceAllocSize, px_height * bytesPerRow);
    NSDictionary *options = @{
        (id)kIOSurfaceWidth: @(px_width),
        (id)kIOSurfaceHeight: @(px_height),
        (id)kIOSurfacePixelFormat: @(pixelFormat),
        (id)kIOSurfaceBytesPerElement: @(bytesPerElement),
        (id)kIOSurfaceBytesPerRow: @(bytesPerRow),
        (id)kIOSurfaceAllocSize: @(totalBytes),
    };
    io_surface = IOSurfaceCreate((CFDictionaryRef)options);
    printf("io_surface: %p\n", io_surface);
  }

  {

    // Map the IOSurface, write some values.
    uint8_t* data = reinterpret_cast<uint8_t*>(
        IOSurfaceGetBaseAddressOfPlane(io_surface, 0 /* planeIndex */));
    assert(data);

    const uint8_t color[] = {0x30, 0x40, 0x10, 0x00};
    const size_t stride = IOSurfaceGetBytesPerRowOfPlane(io_surface, 0);
    for (int y = 0; y < px_height; ++y) {
      for (int x = 0; x < px_width; ++x) {
        *reinterpret_cast<uint32_t*>(&data[y * stride + x * 4]) =
            0x3 << 30 |  // Alpha channel is unused
            ((color[0] << 2) | (color[0] >> 6)) << 20 |  // R
            ((color[1] << 2) | (color[1] >> 6)) << 10 |  // G
            ((color[2] << 2) | (color[2] >> 6));         // B
      }
    }
  }

  // Create a GL context.
  {
    CGLPixelFormatAttribute attribs[] = {static_cast<CGLPixelFormatAttribute>(0)};
    GLint number_virtual_screens = 0;
    CGLChoosePixelFormat(attribs, &cgl_pixel_format, &number_virtual_screens);

    CGLCreateContext(cgl_pixel_format, NULL, &cgl_context);
    printf("cgl_context: %p\n", cgl_context);

    CGLSetCurrentContext(cgl_context);
    glGenTextures(1, &gl_texture);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, gl_texture);
    glTexParameterf(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameterf(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    CGLError cgl_error = CGLTexImageIOSurface2D(
        CGLGetCurrentContext(),
        GL_TEXTURE_RECTANGLE_ARB,
        GL_RGBA,
        px_width,
        px_height,
        GL_BGRA,
        GL_UNSIGNED_INT_2_10_10_10_REV,
        io_surface,
        0 /* plane */);
    printf("CGLTexImageIOSurface2D %d\n", cgl_error);

    glGenFramebuffers(1, &gl_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, gl_fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_RECTANGLE_ARB, gl_texture, 0);
    printf("FBO complete: %d\n", glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);

    //glClearColor(0.5, 0.5, 0.5, 1);
    //glClear(GL_COLOR_BUFFER_BIT);
    glFlush();
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    CGLSetCurrentContext(NULL);
    printf("GL error at initial clear: %d\n", glGetError());
  }

  // Create a CGImage from the IOSurface.
  {
    [main_layer setContents:(id)io_surface];
    [main_layer setBounds:CGRectMake(0, 0, width, height)];
    [main_layer setContentsScale:scale_factor];
  }

  [view addSubview:main_view];

  //DisplayLinkInit();

  [NSApp activateIgnoringOtherApps:YES];
  [NSApp run];
  return 0;
}

