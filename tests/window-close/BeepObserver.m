// Observe the cross-framework system alert calls used by AppKit. Interposing
// NSBeep alone misses direct calls within the dyld shared cache.
#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#include <stdio.h>

#ifdef BEEP_OBSERVER_CONTROL
@interface CloseDelegate : NSObject <NSWindowDelegate>
@end
@implementation CloseDelegate
- (BOOL)windowShouldClose:(NSWindow *)window {
    [window orderOut:nil];
    return NO;
}
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Both positive controls must be observed before trusting a silent test.
        NSBeep();
        NSWindow *invalid = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [invalid performClose:nil];
        CloseDelegate *delegate = [CloseDelegate new];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:NO];
        window.delegate = delegate;
        // A delegate that handles closing and returns NO must not add a beep.
        [window performClose:nil];
    }
    return 0;
}
#else
static void recordSound(SystemSoundID sound) {
    fprintf(stderr, "WINDOW_CLOSE_ALERT %u\n", sound);
}
static void recordCompletion(SystemSoundID sound, void (^completion)(void)) {
    recordSound(sound);
    if (completion) completion();
}
#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *newFunction; const void *oldFunction; } \
    pair_##original __attribute__((section("__DATA,__interpose"))) = \
        { (const void *)replacement, (const void *)original }
INTERPOSE(recordSound, AudioServicesPlaySystemSound);
INTERPOSE(recordSound, AudioServicesPlayAlertSound);
INTERPOSE(recordCompletion, AudioServicesPlaySystemSoundWithCompletion);
INTERPOSE(recordCompletion, AudioServicesPlayAlertSoundWithCompletion);
__attribute__((constructor)) static void loaded(void) {
    fprintf(stderr, "WINDOW_CLOSE_OBSERVER_LOADED\n");
}
#endif
