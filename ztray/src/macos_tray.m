#import <AppKit/AppKit.h>
#include <stdbool.h>
#include <stdatomic.h>

static NSStatusItem *ztray_tray_status_item = nil;
static NSMenu *ztray_tray_menu = nil;
static id ztray_tray_menu_target = nil;
static atomic_int ztray_tray_pending_action_id = -1;

enum {
    // Bit 0: Zig `Modifier.primary` → Command on macOS.
    ZTrayTrayModifierCommand = 1u << 0,
    ZTrayTrayModifierShift = 1u << 1,
    ZTrayTrayModifierOption = 1u << 2,
    ZTrayTrayModifierControl = 1u << 3,
    ZTrayTrayModifierSuper = 1u << 4,
};

@interface ZTrayTrayMenuTarget : NSObject
- (void)performZTrayTrayAction:(id)sender;
@end

@implementation ZTrayTrayMenuTarget
- (void)performZTrayTrayAction:(id)sender {
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : -1;
    (void)[sender isKindOfClass:[NSMenuItem class]];
    atomic_store(&ztray_tray_pending_action_id, (int)tag);
}
@end

static NSString *ztrayTrayString(const char *value) {
    if (value == NULL) return @"";
    return [NSString stringWithUTF8String:value] ?: @"";
}

static NSEventModifierFlags ztrayTrayModifierFlags(unsigned int modifiers) {
    NSEventModifierFlags flags = 0;
    if ((modifiers & ZTrayTrayModifierCommand) != 0) flags |= NSEventModifierFlagCommand;
    if ((modifiers & ZTrayTrayModifierSuper) != 0) flags |= NSEventModifierFlagCommand;
    if ((modifiers & ZTrayTrayModifierShift) != 0) flags |= NSEventModifierFlagShift;
    if ((modifiers & ZTrayTrayModifierOption) != 0) flags |= NSEventModifierFlagOption;
    if ((modifiers & ZTrayTrayModifierControl) != 0) flags |= NSEventModifierFlagControl;
    return flags;
}

bool ZTrayMacOSTrayInstall(const char *tooltip, const char *icon_path_utf8_or_null, const unsigned char *png_bytes, size_t png_len) {
    if (ztray_tray_status_item != nil) return false;

    if (ztray_tray_menu_target == nil) {
        ztray_tray_menu_target = [[ZTrayTrayMenuTarget alloc] init];
        if (ztray_tray_menu_target == nil) return false;
    }

    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    ztray_tray_status_item = [bar statusItemWithLength:NSSquareStatusItemLength];
    if (ztray_tray_status_item == nil) return false;

    ztray_tray_menu = [[NSMenu alloc] initWithTitle:@"Tray"];
    if (ztray_tray_menu == nil) {
        [[NSStatusBar systemStatusBar] removeStatusItem:ztray_tray_status_item];
        ztray_tray_status_item = nil;
        return false;
    }

    ztray_tray_status_item.menu = ztray_tray_menu;
    ztray_tray_status_item.button.toolTip = ztrayTrayString(tooltip);

    if (png_len > 0 && png_bytes != NULL) {
        NSData *d = [NSData dataWithBytes:png_bytes length:png_len];
        NSImage *img = [[NSImage alloc] initWithData:d];
        if (img != nil) {
            img.size = NSMakeSize(18, 18);
            ztray_tray_status_item.button.image = img;
        }
    } else if (icon_path_utf8_or_null != NULL && icon_path_utf8_or_null[0] != '\0') {
        NSString *p = [NSString stringWithUTF8String:icon_path_utf8_or_null];
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:p];
        if (img != nil) {
            img.size = NSMakeSize(18, 18);
            ztray_tray_status_item.button.image = img;
        }
    }
    if (ztray_tray_status_item.button.image == nil) {
        ztray_tray_status_item.button.title = @"●";
    }

    return true;
}

bool ZTrayMacOSTrayClearMenu(void) {
    if (ztray_tray_menu == nil) return false;
    [ztray_tray_menu removeAllItems];
    return true;
}

bool ZTrayMacOSTrayAddItem(const char *title, int action_id, const char *key, unsigned int modifiers, bool enabled, bool suppress_next_window_close) {
    (void)suppress_next_window_close;
    if (ztray_tray_menu == nil) return false;

    NSMenuItem *item = [ztray_tray_menu addItemWithTitle:ztrayTrayString(title) action:@selector(performZTrayTrayAction:) keyEquivalent:ztrayTrayString(key)];
    if (item == nil) return false;

    item.target = ztray_tray_menu_target;
    item.tag = action_id;
    item.enabled = enabled ? YES : NO;
    item.keyEquivalentModifierMask = ztrayTrayModifierFlags(modifiers);
    return true;
}

bool ZTrayMacOSTrayAddSeparator(void) {
    if (ztray_tray_menu == nil) return false;
    [ztray_tray_menu addItem:NSMenuItem.separatorItem];
    return true;
}

int ZTrayMacOSTrayPollAction(void) {
    return atomic_exchange(&ztray_tray_pending_action_id, -1);
}

void ZTrayMacOSTrayShutdown(void) {
    if (ztray_tray_status_item != nil) {
        ztray_tray_status_item.menu = nil;
        [[NSStatusBar systemStatusBar] removeStatusItem:ztray_tray_status_item];
        ztray_tray_status_item = nil;
    }
    ztray_tray_menu = nil;
    ztray_tray_menu_target = nil;
    atomic_store(&ztray_tray_pending_action_id, -1);
}

void ZTrayMacOSPumpEventsTimeoutMs(unsigned ms) {
    NSApplication *app = NSApplication.sharedApplication;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: (NSTimeInterval)ms / 1000.0];
    NSEvent *ev = [app nextEventMatchingMask:NSEventMaskAny untilDate:until inMode:NSDefaultRunLoopMode dequeue:YES];
    if (ev != nil) [app sendEvent:ev];
    [app updateWindows];
}
