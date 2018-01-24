// Compile with:
//
// clang++ rgb10_a2_iosurface_glReadPixels.mm -framework AppKit -framework OpenGL -framework IOSurface -framework CoreVideo -o rgb10 -g
//
#include <string>

#import  <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <OpenGL/OpenGL.h>
//#include <OpenGL/GLU.h>
#include <OpenGL/GLext.h>
#include <OpenGL/gl3.h>


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

NSView* main_view = nil;
CVDisplayLinkRef g_display_link = NULL;

uint8_t pixels[px_width * px_height * 4] = {0};

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
  [window setTitle:@"Write IOSurface and read back with glReadPixels()"];
  [window makeKeyAndOrderFront:nil];

  NSOpenGLPixelFormatAttribute pixelFormatAttributes[] = {
      NSOpenGLPFAColorSize,   24,
      NSOpenGLPFAAlphaSize, 8,
      NSOpenGLPFAAccelerated, 0};
  NSOpenGLPixelFormat *pixelFormat =
      [[NSOpenGLPixelFormat alloc] initWithAttributes:pixelFormatAttributes];
  main_view = [[NSView alloc] initWithFrame:[view bounds]];

  [view setWantsLayer:YES];

  // Create an IOSurface.
  const unsigned ioPixelFormat = 'R10k';
  const unsigned bytesPerElement = 4;
  const size_t bytesPerRow =
      IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, px_width * bytesPerElement);
  const size_t totalBytes =
      IOSurfaceAlignProperty(kIOSurfaceAllocSize, px_height * bytesPerRow);
  NSDictionary *options = @{
    (id)kIOSurfaceWidth : @(px_width),
    (id)kIOSurfaceHeight : @(px_height),
    (id)kIOSurfacePixelFormat : @(ioPixelFormat),
    (id)kIOSurfaceBytesPerElement : @(bytesPerElement),
    (id)kIOSurfaceBytesPerRow : @(bytesPerRow),
    (id)kIOSurfaceAllocSize : @(totalBytes),
  };
  io_surface = IOSurfaceCreate((CFDictionaryRef)options);
  if (!io_surface) {
    printf("error creating IOSurface\n");
    assert(false);
  } else {
    printf("IOSurface created OK\n");
  }

  // Map the IOSurface, write some values.
  uint8_t* data = reinterpret_cast<uint8_t*>(
      IOSurfaceGetBaseAddressOfPlane(io_surface, 0 /* planeIndex */));
  assert(data);

  const uint8_t color[] = {0x30, 0x40, 0x10, 0xFF};
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
  printf("IOSurface written: %dx%d pixels (stride %luB)\n", px_width,
         px_height, stride);

  // Create a CGL context.
  CGLPixelFormatAttribute attribs[] = {
      kCGLPFAOpenGLProfile,
      (CGLPixelFormatAttribute)NSOpenGLProfileVersion3_2Core,
      (CGLPixelFormatAttribute)0};
  GLint number_virtual_screens = 0;
  CGLChoosePixelFormat(attribs, &cgl_pixel_format, &number_virtual_screens);
  CGLCreateContext(cgl_pixel_format, NULL, &cgl_context);
  printf("cgl_context: %p\n", cgl_context);
  CGLSetCurrentContext(cgl_context);

  printf("Using [%s - %s]\n", glGetString(GL_VENDOR), glGetString(GL_RENDERER));

  // Bind the |io_surface| to a texture.
  glGenTextures(1, &gl_texture);
  glBindTexture(GL_TEXTURE_RECTANGLE_ARB, gl_texture);
  glTexParameterf(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameterf(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  CGLError cgl_error = CGLTexImageIOSurface2D(
      CGLGetCurrentContext(),
      GL_TEXTURE_RECTANGLE_ARB,
      GL_RGB10_A2,
      px_width,
      px_height,
      GL_BGRA,
      GL_UNSIGNED_INT_2_10_10_10_REV,
      io_surface,
      0 /* plane */);
  if (cgl_error != kCGLNoError) {
    printf("CGLTexImageIOSurface2D %s\n", CGLErrorString(cgl_error));
    assert(false);
  } else {
    printf("CGLTexImageIOSurface2D OK\n");
  }

  if (0) {
    // Generate a FrameBuffer, link it to our IOSurface-backed Texture.
    glGenFramebuffers(1, &gl_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, gl_fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_RECTANGLE_ARB, gl_texture, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      printf("error creating/binding FBO\n");
      assert(false);
    } else {
      printf("FBO complete OK\n");
    }
    printf("FBO: %d\n", glGetError());

    GLenum DrawBuffers[1] = {GL_COLOR_ATTACHMENT0};
    glDrawBuffers(1, DrawBuffers);
    printf("glDrawBuffers: %d\n", glGetError());

    // Read back.
    glReadPixels(0, 0, px_width, px_height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    printf("glReadPixels: %d\n", glGetError());

    for (int y = 0; y < px_height; ++y) {
      for (int x = 0; x < px_width; ++x) {
        const int pixel_index = y * stride + x * 4;
        assert(pixels[pixel_index] == color[0]);
        assert(pixels[pixel_index + 1] == color[1]);
        assert(pixels[pixel_index + 2] == color[2]);
        assert(pixels[pixel_index + 3] == color[3]);
      }
    }
    printf("Success: all pixels are correctly read back\n");

  } else {

    // Generate and bind a FrameBuffer, render to texture type.
    {
      GLuint texture = 0;
      const GLuint target = GL_TEXTURE_2D;
      glGenTextures(1, &texture);
      glBindTexture(target, texture);
      glTexParameteri(target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(target, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexImage2D(target, 0, GL_RGBA, px_width, px_height, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, nullptr);

      glGenFramebuffersEXT(1, &gl_fbo);
      glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, gl_fbo);
      glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0,
                                target, texture, 0);
      if (glCheckFramebufferStatusEXT(GL_FRAMEBUFFER) !=
          GL_FRAMEBUFFER_COMPLETE) {
        printf("error creating/binding FBO\n");
        assert(false);
      } else {
        printf("FBO complete OK\n");
      }

      glBindFramebufferEXT(GL_FRAMEBUFFER, 0);
      glDeleteTextures(1, &texture);
      assert(gl_fbo);
    }

    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, gl_fbo);
    glClearColor(0.3, 0.6, 1.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    printf("GL error at initial clear: %d\n", glGetError());

    glViewport(0, 0, px_width, px_height);

    //////////////////////////////////////////////////////////////////////////////
    static const char* vertex_shader_code[] = {
       "#version 150\n\
        in vec2 a_position;\n\
        out vec2 v_texCoord;\n\
        void main() {\n\
          gl_Position = vec4(a_position.x, a_position.y, 0.0, 1.0);\n\
          v_texCoord = (a_position + vec2(1.0, 1.0)) * 0.5;\n\
        }"};
    //static const char* vertex_shader_code[] = {
    //  "#version 330\n\
    //   layout(location = 0) in vec4 in_position;\n\
    //   void main()\n\
    //   {\n\
    //     gl_Position = in_position;\n\
    //   }"};

    GLuint vertex_shader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertex_shader, 1, vertex_shader_code, nullptr);
    printf("glShaderSource: %d\n", glGetError());
    glCompileShader(vertex_shader);
    printf("glCompileShader: %d\n", glGetError());

    GLint value = 0;
    glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, &value);
    if (!value) {
      char buffer[1024] = {0};
      GLsizei length = 0;
      glGetShaderInfoLog(vertex_shader, sizeof(buffer), &length, buffer);
      printf("Error compiling |vertex_shader|: %s\n", buffer);
      glDeleteShader(vertex_shader);
      assert(false);
    }

    //////////////////////////////////////////////////////////////////////////////
    static const char* fragment_shader_code[] = {
        "#version 150\n\
         #define SamplerType sampler2DRect\n\
         #define TextureLookup texture\n\
         #define TextureScale vec2(256.000000, 256.000000)\n\
         uniform SamplerType a_texture;\n\
         in vec2 v_texCoord;\n\
         out vec4 my_FragData;\n\
         void main() {\n\
           my_FragData = TextureLookup(a_texture, v_texCoord * TextureScale);\n\
         }"};
    //static const char* fragment_shader_code[] = {
    //    "#version 330\n\
    //     uniform sampler2D tex;\n\
    //     uniform vec2 tex_size;\n\
    //     layout(location = 0) out vec4 out_color;\n\
    //     void main()\n\
    //     {\n\
    //         vec4 in_color = texture(tex, gl_FragCoord.xy / tex_size);\n\
    //         out_color = in_color;\n\
    //     }"};

    GLuint fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragment_shader, 1, fragment_shader_code, nullptr);
    glCompileShader(fragment_shader);

    value = 0;
    glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, &value);
    if (!value) {
      char buffer[1024] = {0};
      GLsizei length = 0;
      glGetShaderInfoLog(fragment_shader, sizeof(buffer), &length, buffer);
      printf("Error compiling |fragment_shader|: %s\n", buffer);
      glDeleteShader(fragment_shader);
      assert(false);
    }

    //////////////////////////////////////////////////////////////////////////////
    GLuint program = glCreateProgram();
    glAttachShader(program, vertex_shader);
    glAttachShader(program, fragment_shader);
    glLinkProgram(program);

    GLint linked = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (!linked) {
      char buffer[1024];
      GLsizei length = 0;
      glGetProgramInfoLog(program, sizeof(buffer), &length, buffer);
      std::string log(buffer, length);
      printf("Error linking |program|: %s\n", buffer);
      glDeleteProgram(program);
      assert(false);
    }
    glUseProgram(program);

    GLint sampler_location = glGetUniformLocation(program, "a_texture");
    assert(sampler_location != -1);
    glUniform1i(sampler_location, 0);


    GLuint vertex_array;
    glGenVertexArrays(1, &vertex_array);
    glBindVertexArray(vertex_array);

    //GLuint vertex_buffer = 0;
    //glGenBuffers(1, &vertex_buffer);
    //glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer);
    GLfloat quad[] = {-1.f, -1.f,
                       1.f, -1.f,
                      -1.f,  1.f,
                       1.f,  1.f};
    //glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    //printf("glBufferData: %d\n", glGetError());

    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 2, NULL);
    printf("glVertexAttribPointer: %d\n", glGetError());

    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, gl_texture);
    printf("glBindTexture: %d\n", glGetError());
    glBindVertexArray(vertex_array);

    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    printf("glDrawArrays: %d\n", glGetError());

    glReadPixels(0, 0, px_width, px_height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    printf("glReadPixels: %d\n", glGetError());

    glFlush();


    for (int y = 0; y < 10; ++y) {
      for (int x = 0; x < 10; ++x) {
        const int pixel_index = y * stride + x * 4;
        printf("0x%x 0x%x 0x%x 0x%x-\n", pixels[pixel_index], pixels[pixel_index+1],
          pixels[pixel_index+2], pixels[pixel_index+3]);
        //assert(pixels[pixel_index] == color[0]);
        //assert(pixels[pixel_index + 1] == color[1]);
        //assert(pixels[pixel_index + 2] == color[2]);
        //assert(pixels[pixel_index + 3] == color[3]);
      }
    }
    printf("Success: all pixels are correctly read back\n");
  }

  // TODO: cleanup.


  [view addSubview:main_view];

  [NSApp activateIgnoringOtherApps:YES];
  //[NSApp run];
  return 0;
}

