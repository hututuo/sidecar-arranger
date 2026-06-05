/*
 * Sidecar Arranger position picker.
 *
 * Prints one of: left / right / above / below / ignore / cancel
 */

#import <Cocoa/Cocoa.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp activateIgnoringOtherApps:YES];

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Sidecar Arranger"];
        [alert setInformativeText:@"iPad/Sidecar 显示器放在 MacBook 的哪里？\n如果这不是 iPad，可以选择忽略此显示器。"];
        [alert addButtonWithTitle:@"右边"];
        [alert addButtonWithTitle:@"左边"];
        [alert addButtonWithTitle:@"上方"];
        [alert addButtonWithTitle:@"下方"];
        [alert addButtonWithTitle:@"忽略此显示器，以后不再弹窗"];
        NSButton *cancelButton = [alert addButtonWithTitle:@"取消"];
        [cancelButton setKeyEquivalent:@"\033"];
        [alert setAlertStyle:NSAlertStyleInformational];

        NSWindow *window = [alert window];
        [window setLevel:NSFloatingWindowLevel];

        NSScreen *main = [NSScreen mainScreen];
        NSRect frame = main.frame;
        NSRect winFrame = window.frame;
        CGFloat x = NSMidX(frame) - winFrame.size.width / 2;
        CGFloat y = NSMidY(frame) - winFrame.size.height / 2;
        [window setFrameOrigin:NSMakePoint(x, y)];

        NSModalResponse r = [alert runModal];

        if      (r == NSAlertFirstButtonReturn)  printf("right\n");
        else if (r == NSAlertSecondButtonReturn) printf("left\n");
        else if (r == NSAlertThirdButtonReturn)  printf("above\n");
        else if (r == NSAlertThirdButtonReturn + 1) printf("below\n");
        else if (r == NSAlertThirdButtonReturn + 2) printf("ignore\n");
        else printf("cancel\n");
    }
    return 0;
}
