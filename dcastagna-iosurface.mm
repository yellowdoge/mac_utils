// clang++ iosurface-contents.mm -framework IOSurface -framework QuartzCore -framework Cocoa -framework OpenGL
#import  <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#import <OpenGL/gl.h>
#import <OpenGL/CGLTypes.h>
#import <OpenGL/CGLCurrent.h>

IOSurfaceRef io_surfaces[2];

@interface CALayer (Private)
- (void)setContentsChanged;
@end

CALayer* main_layer = nil;

@interface MainWindow : NSWindow
- (void)updateFrame;
@end

CGLContextObj context;
GLuint framebuffers[2];
int activeFramebuffer = 0;

void CreateCGLContext() {
  // Create CGL Context
  CGLPixelFormatAttribute attributes[4] = {
    kCGLPFAAccelerated, kCGLPFAOpenGLProfile,
    (CGLPixelFormatAttribute) kCGLOGLPVersion_3_2_Core,
    (CGLPixelFormatAttribute) 0
  };
  CGLPixelFormatObj pix;
  CGLError err;
  GLint num;
  err = CGLChoosePixelFormat( attributes, &pix, &num );
  if (err != kCGLNoError) {
    printf("Error in CGLChoosePixelFormat\n");
  }
  err = CGLCreateContext( pix, NULL, &context);
  if (err != kCGLNoError) {
    printf("Error in CGLCreateContext\n");
  }
  CGLDestroyPixelFormat( pix );
  err = CGLSetCurrentContext( context );
  if (err != kCGLNoError) {
    printf("Error in CGLCreateContext\n");
  }

  for (int i=0; i<2; i++) {
    GLuint texture;
    glActiveTexture(GL_TEXTURE0);
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texture);
    err =
      CGLTexImageIOSurface2D(context, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA,
			     IOSurfaceGetWidth(io_surfaces[i]), IOSurfaceGetHeight(io_surfaces[i]),
			     GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, io_surfaces[i], 0);
    if (err != kCGLNoError) {
      printf("Error in CGLTexImageIOSurface2D: %s\n", CGLErrorString(err));
    }
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
    glGenFramebuffers(1, &framebuffers[i]);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffers[i]);
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			      GL_TEXTURE_RECTANGLE_ARB, texture, 0);
  }
}

void DrawToIOSurface() {
  // If IOSurfaceIsInUse(io_surface) allocate new IOSurface or wait.

  if (IOSurfaceIsInUse(io_surfaces[activeFramebuffer]))
    return;
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffers[activeFramebuffer]);

  glClearColor(activeFramebuffer ? 1.0 : 0.0, 0.5f, 0.5f, 1.0f);

  // Just clearing the fb.
  glClear(GL_COLOR_BUFFER_BIT);
  glFlush();
}

@implementation MainWindow

- (void)updateFrame {
  [self performSelector:@selector(updateFrame) withObject:nil afterDelay:1./60.];

  activeFramebuffer = (activeFramebuffer + 1) % 2;
  DrawToIOSurface();
  [CATransaction begin];
  [CATransaction setValue:[NSNumber numberWithBool:YES]
                   forKey:kCATransactionDisableActions];
  [main_layer setContents:(id)io_surfaces[activeFramebuffer]];
  [CATransaction commit];
}
@end


int main(int argc, char* argv[]) {
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  MainWindow* window = [[MainWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 1024, 768)
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:NO];
  NSView* view = [window contentView];
  [window setTitle:@"CALayer with double-buffered IOSurface content updated by GL"];
  [window setFrameOrigin:NSMakePoint(20, 20)];
  [window makeKeyAndOrderFront:nil];

  // Create IOSurface
  unsigned pixelFormat = 'BGRA';
  NSDictionary *options = @{
    (id)kIOSurfaceWidth: @(1024),
    (id)kIOSurfaceHeight: @(768),
    (id)kIOSurfacePixelFormat: @(pixelFormat),
    (id)kIOSurfaceBytesPerElement: @(4),
  };

  for (int i=0; i<2; i++)
    io_surfaces[i] = IOSurfaceCreate((CFDictionaryRef)options);

  CreateCGLContext();

  main_layer = [[CALayer alloc] init];
  [main_layer setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
  [main_layer setFrame:CGRectMake(0, 0, 1024, 768)];
  [view setLayer:main_layer];
  [view setWantsLayer:YES];

  [window updateFrame];

  [NSApp activateIgnoringOtherApps:YES];
  [NSApp run];
  return 0;
}
