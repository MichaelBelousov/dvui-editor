#import <AppKit/AppKit.h>
#include <stdbool.h>
#include <stdatomic.h>
#import <objc/runtime.h>

static bool ztray_menu_bar_set_up = false;
static atomic_int ztray_pending_action_id = -1;
static atomic_bool ztray_suppress_close_tab_close = false;
static const void *ZTrayWindowDelegateProxyAssociationKey = &ZTrayWindowDelegateProxyAssociationKey;
static NSMenu *ztray_pending_main_menu = nil;
static NSMenu *ztray_pending_menu = nil;
static id ztray_menu_target = nil;

enum {
    ZTrayModifierCommand = 1u << 0,
    ZTrayModifierShift = 1u << 1,
    ZTrayModifierOption = 1u << 2,
    ZTrayModifierControl = 1u << 3,
};

@interface ZTrayWindowDelegateProxy : NSObject <NSWindowDelegate>
@property (nonatomic, assign) id<NSWindowDelegate> originalDelegate;
@property (nonatomic, assign) BOOL suppressNextWindowClose;
- (instancetype)initWithOriginalDelegate:(id<NSWindowDelegate>)originalDelegate;
@end

@implementation ZTrayWindowDelegateProxy
- (instancetype)initWithOriginalDelegate:(id<NSWindowDelegate>)originalDelegate {
    self = [super init];
    if (self != nil) {
        _originalDelegate = originalDelegate;
        _suppressNextWindowClose = NO;
    }
    return self;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (self.suppressNextWindowClose) {
        self.suppressNextWindowClose = NO;
        return NO;
    }
    if ([self.originalDelegate respondsToSelector:@selector(windowShouldClose:)]) {
        return [self.originalDelegate windowShouldClose:sender];
    }
    return YES;
}

- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.originalDelegate respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
    if ([self.originalDelegate respondsToSelector:selector]) {
        return self.originalDelegate;
    }
    return [super forwardingTargetForSelector:selector];
}
@end

static ZTrayWindowDelegateProxy *ztrayInstallWindowDelegateProxy(NSWindow *window) {
    if (window == nil) return nil;

    ZTrayWindowDelegateProxy *proxy = objc_getAssociatedObject(window, ZTrayWindowDelegateProxyAssociationKey);
    if (proxy != nil) return proxy;

    id<NSWindowDelegate> originalDelegate = window.delegate;
    if ([originalDelegate isKindOfClass:[ZTrayWindowDelegateProxy class]]) {
        return (ZTrayWindowDelegateProxy *)originalDelegate;
    }

    proxy = [[ZTrayWindowDelegateProxy alloc] initWithOriginalDelegate:originalDelegate];
    if (proxy == nil) return nil;

    objc_setAssociatedObject(window, ZTrayWindowDelegateProxyAssociationKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.delegate = proxy;
    return proxy;
}

static void ztraySuppressNextWindowCloseForCurrentWindow(void) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow;
    ZTrayWindowDelegateProxy *proxy = ztrayInstallWindowDelegateProxy(window);
    if (proxy != nil) {
        proxy.suppressNextWindowClose = YES;
    }
}

@interface ZTrayMenuTarget : NSObject
- (void)performZTrayAction:(id)sender;
@end

@implementation ZTrayMenuTarget
- (void)performZTrayAction:(id)sender {
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : -1;

    if ([sender isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *item = (NSMenuItem *)sender;
        id rep = item.representedObject;
        if ([rep isKindOfClass:[NSNumber class]] && [(NSNumber *)rep boolValue]) {
            ztraySuppressNextWindowCloseForCurrentWindow();
            atomic_store(&ztray_suppress_close_tab_close, true);
        }
    }

    atomic_store(&ztray_pending_action_id, (int)tag);
}
@end

static NSString *ztrayString(const char *value) {
    if (value == NULL) return @"";
    return [NSString stringWithUTF8String:value] ?: @"";
}

static NSEventModifierFlags ztrayModifierFlags(unsigned int modifiers) {
    NSEventModifierFlags flags = 0;
    if ((modifiers & ZTrayModifierCommand) != 0) flags |= NSEventModifierFlagCommand;
    if ((modifiers & ZTrayModifierShift) != 0) flags |= NSEventModifierFlagShift;
    if ((modifiers & ZTrayModifierOption) != 0) flags |= NSEventModifierFlagOption;
    if ((modifiers & ZTrayModifierControl) != 0) flags |= NSEventModifierFlagControl;
    return flags;
}

static NSMenu *ztrayEnsureMainMenu(NSApplication *app) {
    NSMenu *mainMenu = app.mainMenu;
    if (mainMenu != nil) return mainMenu;

    mainMenu = [[NSMenu alloc] initWithTitle:@""];
    if (mainMenu == nil) return nil;

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    if (appItem == nil) return nil;
    [mainMenu addItem:appItem];

    NSString *appName = NSProcessInfo.processInfo.processName ?: @"Application";
    NSMenu *appSubmenu = [[NSMenu alloc] initWithTitle:appName];
    if (appSubmenu == nil) return nil;

    [appSubmenu addItemWithTitle:[@"About " stringByAppendingString:appName] action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appSubmenu addItem:NSMenuItem.separatorItem];
    [appSubmenu addItemWithTitle:[@"Hide " stringByAppendingString:appName] action:@selector(hide:) keyEquivalent:@"h"];

    NSMenuItem *hideOthers = [appSubmenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;

    [appSubmenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appSubmenu addItem:NSMenuItem.separatorItem];
    [appSubmenu addItemWithTitle:[@"Quit " stringByAppendingString:appName] action:@selector(terminate:) keyEquivalent:@"q"];

    appItem.submenu = appSubmenu;
    app.mainMenu = mainMenu;
    return mainMenu;
}

static void ztrayAddWindowMenu(NSMenu *mainMenu) {
    if (mainMenu == nil || [mainMenu itemWithTitle:@"Window"] != nil) return;

    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    if (windowMenu == nil) return;

    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];

    NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    if (windowItem == nil) return;
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];
}

bool ZTrayMacOSBeginMainMenu(void) {
    if (ztray_menu_bar_set_up) return false;

    NSApplication *app = NSApplication.sharedApplication;
    NSMenu *mainMenu = ztrayEnsureMainMenu(app);
    if (mainMenu == nil) return false;

    if (ztray_menu_target == nil) {
        ztray_menu_target = [[ZTrayMenuTarget alloc] init];
        if (ztray_menu_target == nil) return false;
    }

    ztray_pending_main_menu = mainMenu;
    ztray_pending_menu = nil;
    return true;
}

bool ZTrayMacOSBeginMenu(const char *title) {
    if (ztray_pending_main_menu == nil || ztray_pending_menu != nil) return false;
    ztray_pending_menu = [[NSMenu alloc] initWithTitle:ztrayString(title)];
    return ztray_pending_menu != nil;
}

bool ZTrayMacOSAddItem(const char *title, int action_id, const char *key, unsigned int modifiers, bool enabled, bool suppress_next_window_close) {
    if (ztray_pending_menu == nil) return false;

    NSMenuItem *item = [ztray_pending_menu addItemWithTitle:ztrayString(title) action:@selector(performZTrayAction:) keyEquivalent:ztrayString(key)];
    if (item == nil) return false;

    item.target = ztray_menu_target;
    item.tag = action_id;
    item.enabled = enabled ? YES : NO;
    item.keyEquivalentModifierMask = ztrayModifierFlags(modifiers);
    item.representedObject = suppress_next_window_close ? @YES : @NO;
    return true;
}

bool ZTrayMacOSAddSeparator(void) {
    if (ztray_pending_menu == nil) return false;
    [ztray_pending_menu addItem:NSMenuItem.separatorItem];
    return true;
}

bool ZTrayMacOSEndMenu(void) {
    if (ztray_pending_main_menu == nil || ztray_pending_menu == nil) return false;

    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:ztray_pending_menu.title action:nil keyEquivalent:@""];
    if (menuItem == nil) return false;

    menuItem.submenu = ztray_pending_menu;
    NSUInteger index = MAX((NSUInteger)1, ztray_pending_main_menu.numberOfItems);
    NSMenuItem *windowItem = [ztray_pending_main_menu itemWithTitle:@"Window"];
    if (windowItem != nil) index = [ztray_pending_main_menu indexOfItem:windowItem];
    [ztray_pending_main_menu insertItem:menuItem atIndex:index];

    ztray_pending_menu = nil;
    return true;
}

bool ZTrayMacOSEndMainMenu(void) {
    if (ztray_pending_main_menu == nil || ztray_pending_menu != nil) return false;
    ztrayAddWindowMenu(ztray_pending_main_menu);
    ztray_pending_main_menu = nil;
    ztray_menu_bar_set_up = true;
    return true;
}

int ZTrayMacOSPollAction(void) {
    return atomic_exchange(&ztray_pending_action_id, -1);
}

bool ZTrayMacOSConsumeCloseTabSuppression(void) {
    return atomic_exchange(&ztray_suppress_close_tab_close, false);
}
