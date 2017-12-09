#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

int main() {
  NSArray* screens = [NSScreen screens];
  for(NSScreen* screen in screens) {
    NSLog(@"\n|deviceDescription|: %@", screen.deviceDescription);
    //NSLog(@"bits per pixel: %ld, bits per sample %ld", 
    //    NSBitsPerPixelFromDepth([screen depth]), 
    //    NSBitsPerSampleFromDepth([screen depth]));
  }
}
