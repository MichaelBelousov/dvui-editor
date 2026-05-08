#import <AppKit/AppKit.h>
#include <stdbool.h>
#include <stdatomic.h>
#import <objc/runtime.h>

static const NSUInteger PixiFullSizeContentViewMask = 1u << 15;
static const NSVisualEffectMaterial PixiVisualEffectMaterial = 15;
static bool pixi_menu_bar_set_up = false;
static atomic_int pixi_pending_native_menu_action_id = -1;
static atomic_bool pixi_suppress_close_tab_close = false;
static const void *PixiWindowDelegateProxyAssociationKey = &PixiWindowDelegateProxyAssociationKey;

static void pixiSuppressNextWindowCloseForCurrentWindow(void);

@interface PixiVisualEffectView : NSVisualEffectView
@end

@implementation PixiVisualEffectView
- (void)rightMouseDown:(NSEvent *)event {
    NSView *contentView = self.subviews.firstObject;
    if (contentView != nil) {
        [contentView rightMouseDown:event];
        return;
    }
    [super rightMouseDown:event];
}
@end

@interface PixiWindowDelegateProxy : NSObject <NSWindowDelegate>
@property (nonatomic, assign) id<NSWindowDelegate> originalDelegate;
@property (nonatomic, assign) BOOL suppressNextWindowClose;
- (instancetype)initWithOriginalDelegate:(id<NSWindowDelegate>)originalDelegate;
@end

@implementation PixiWindowDelegateProxy
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

@interface PixiMenuTarget : NSObject
- (void)openFolder:(id)sender;
- (void)openFiles:(id)sender;
- (void)save:(id)sender;
- (void)copy:(id)sender;
- (void)paste:(id)sender;
- (void)closeTab:(id)sender;
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (void)toggleExplorer:(id)sender;
- (void)showDvuiDemo:(id)sender;
@end

@implementation PixiMenuTarget
- (void)openFolder:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 0); }
- (void)openFiles:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 1); }
- (void)save:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 2); }
- (void)copy:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 3); }
- (void)paste:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 4); }
- (void)closeTab:(id)sender {
    (void)sender;
    pixiSuppressNextWindowCloseForCurrentWindow();
    atomic_store(&pixi_suppress_close_tab_close, true);
    atomic_store(&pixi_pending_native_menu_action_id, 5);
}
- (void)undo:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 6); }
- (void)redo:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 7); }
- (void)toggleExplorer:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 8); }
- (void)showDvuiDemo:(id)sender { (void)sender; atomic_store(&pixi_pending_native_menu_action_id, 9); }
@end

static void pixiWrapContentViewWithVibrancy(NSWindow *window) {
    NSView *contentView = window.contentView;
    if (contentView == nil) return;

    const NSUInteger fillMask = NSViewWidthSizable | NSViewHeightSizable;
    if ([contentView isKindOfClass:[NSVisualEffectView class]]) {
        NSVisualEffectView *effectView = (NSVisualEffectView *)contentView;
        effectView.material = PixiVisualEffectMaterial;
        effectView.menu = nil;
        NSView *subview = effectView.subviews.firstObject;
        if (subview != nil && window.delegate != nil) {
            subview.nextResponder = (NSResponder *)window.delegate;
        }
        return;
    }

    PixiVisualEffectView *effectView = [[PixiVisualEffectView alloc] init];
    if (effectView == nil) return;

    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.state = NSVisualEffectStateActive;
    effectView.material = PixiVisualEffectMaterial;
    effectView.menu = nil;

    [window setContentView:effectView];
    [effectView addSubview:contentView];
    contentView.menu = nil;
    if (window.delegate != nil) {
        contentView.nextResponder = (NSResponder *)window.delegate;
    }
    contentView.frame = effectView.bounds;
    contentView.autoresizingMask = fillMask;
}

static void pixiSetMenuItemImage(NSMenuItem *menuItem, NSString *symbolName, NSString *accessibilityDescription) {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:accessibilityDescription];
    if (image == nil) return;
    image.template = YES;
    menuItem.image = image;
}

static void pixiAddMenuItem(NSMenu *menu, id target, NSString *title, SEL action, NSString *keyEquivalent, NSEventModifierFlags modifiers) {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:keyEquivalent ?: @""];
    if (item == nil) return;
    item.target = target;
    if (modifiers != 0) item.keyEquivalentModifierMask = modifiers;
}

static void pixiAddMenuItemWithImage(NSMenu *menu, id target, NSString *title, SEL action, NSString *keyEquivalent, NSEventModifierFlags modifiers, NSString *symbolName, NSString *accessibilityDescription) {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:keyEquivalent ?: @""];
    if (item == nil) return;
    item.target = target;
    if (modifiers != 0) item.keyEquivalentModifierMask = modifiers;
    pixiSetMenuItemImage(item, symbolName, accessibilityDescription);
}

static void pixiAddMenuItemWithTarget(NSMenu *menu, id target, NSString *title, SEL action, NSString *keyEquivalent, NSEventModifierFlags modifiers) {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:keyEquivalent ?: @""];
    if (item == nil) return;
    item.target = target;
    if (modifiers != 0) item.keyEquivalentModifierMask = modifiers;
}

static PixiWindowDelegateProxy *pixiInstallWindowDelegateProxy(NSWindow *window) {
    if (window == nil) return nil;

    PixiWindowDelegateProxy *proxy = objc_getAssociatedObject(window, PixiWindowDelegateProxyAssociationKey);
    if (proxy != nil) return proxy;

    id<NSWindowDelegate> originalDelegate = window.delegate;
    if ([originalDelegate isKindOfClass:[PixiWindowDelegateProxy class]]) {
        return (PixiWindowDelegateProxy *)originalDelegate;
    }

    proxy = [[PixiWindowDelegateProxy alloc] initWithOriginalDelegate:originalDelegate];
    if (proxy == nil) return nil;

    objc_setAssociatedObject(window, PixiWindowDelegateProxyAssociationKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.delegate = proxy;
    return proxy;
}

static void pixiSuppressNextWindowCloseForCurrentWindow(void) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow;
    PixiWindowDelegateProxy *proxy = pixiInstallWindowDelegateProxy(window);
    if (proxy != nil) {
        proxy.suppressNextWindowClose = YES;
    }
}

static NSMenu *pixiEnsureMainMenu(NSApplication *app) {
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
    pixiAddMenuItemWithTarget(appSubmenu, nil, [@"Hide " stringByAppendingString:appName], @selector(hide:), @"h", NSEventModifierFlagCommand);
    pixiAddMenuItemWithTarget(appSubmenu, nil, @"Hide Others", @selector(hideOtherApplications:), @"h", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    pixiAddMenuItemWithTarget(appSubmenu, nil, @"Show All", @selector(unhideAllApplications:), @"", 0);
    [appSubmenu addItem:NSMenuItem.separatorItem];
    pixiAddMenuItemWithTarget(appSubmenu, nil, [@"Quit " stringByAppendingString:appName], @selector(terminate:), @"q", NSEventModifierFlagCommand);

    appItem.submenu = appSubmenu;
    app.mainMenu = mainMenu;
    return mainMenu;
}

void PixiMacOSSetWindowStyle(void *window_ptr) {
    NSWindow *window = (__bridge NSWindow *)window_ptr;
    if (window == nil) return;

    pixiInstallWindowDelegateProxy(window);
    window.styleMask |= PixiFullSizeContentViewMask;
    window.titlebarAppearsTransparent = YES;
}

void PixiMacOSSetTitlebarColor(void *window_ptr, double red, double green, double blue, double alpha, bool dark) {
    NSWindow *window = (__bridge NSWindow *)window_ptr;
    if (window == nil) return;

    PixiMacOSSetWindowStyle(window_ptr);
    pixiWrapContentViewWithVibrancy(window);

    window.backgroundColor = [NSColor colorWithRed:red green:green blue:blue alpha:alpha];
    window.appearance = [NSAppearance appearanceNamed:(dark ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)];
    window.hasShadow = YES;
}

bool PixiMacOSSetupMenuBar(void) {
    if (pixi_menu_bar_set_up) return true;

    NSApplication *app = NSApplication.sharedApplication;
    NSMenu *mainMenu = pixiEnsureMainMenu(app);
    if (mainMenu == nil) return false;

    PixiMenuTarget *target = [[PixiMenuTarget alloc] init];
    if (target == nil) return false;

    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    if (fileMenu == nil) return false;

    pixiAddMenuItemWithImage(fileMenu, target, @"Open Folder", @selector(openFolder:), @"f", NSEventModifierFlagCommand, @"folder", @"Open Folder");
    pixiAddMenuItemWithImage(fileMenu, target, @"Open Files", @selector(openFiles:), @"o", NSEventModifierFlagCommand, @"doc.on.doc", @"Open Files");
    [fileMenu addItem:NSMenuItem.separatorItem];
    pixiAddMenuItem(fileMenu, target, @"Save", @selector(save:), @"s", NSEventModifierFlagCommand);
    pixiAddMenuItem(fileMenu, target, @"Close Tab", @selector(closeTab:), @"w", NSEventModifierFlagCommand);

    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    if (fileItem == nil) return false;
    fileItem.submenu = fileMenu;
    [mainMenu insertItem:fileItem atIndex:1];

    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    if (editMenu != nil) {
        pixiAddMenuItem(editMenu, target, @"Copy", @selector(copy:), @"c", NSEventModifierFlagCommand);
        pixiAddMenuItem(editMenu, target, @"Paste", @selector(paste:), @"v", NSEventModifierFlagCommand);
        [editMenu addItem:NSMenuItem.separatorItem];
        pixiAddMenuItem(editMenu, target, @"Undo", @selector(undo:), @"z", NSEventModifierFlagCommand);
        pixiAddMenuItem(editMenu, target, @"Redo", @selector(redo:), @"z", NSEventModifierFlagCommand | NSEventModifierFlagShift);

        NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
        if (editItem != nil) {
            editItem.submenu = editMenu;
            [mainMenu insertItem:editItem atIndex:2];
        }
    }

    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    if (viewMenu != nil) {
        pixiAddMenuItem(viewMenu, target, @"Show Explorer", @selector(toggleExplorer:), @"e", NSEventModifierFlagCommand);
        [viewMenu addItem:NSMenuItem.separatorItem];
        pixiAddMenuItem(viewMenu, target, @"Show DVUI Demo", @selector(showDvuiDemo:), @"", 0);

        NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
        if (viewItem != nil) {
            viewItem.submenu = viewMenu;
            [mainMenu insertItem:viewItem atIndex:3];
        }
    }

    NSMenuItem *appMenuItem = [mainMenu itemAtIndex:0];
    NSMenu *appSubmenu = appMenuItem.submenu;
    if (appSubmenu != nil) {
        NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
        if (windowMenu != nil) {
            pixiAddMenuItemWithTarget(windowMenu, nil, @"Minimize", @selector(performMiniaturize:), @"m", NSEventModifierFlagCommand);
            pixiAddMenuItemWithTarget(windowMenu, nil, @"Zoom", @selector(performZoom:), @"", 0);
            pixiAddMenuItemWithTarget(windowMenu, nil, @"Bring All to Front", @selector(arrangeInFront:), @"", 0);
            [appSubmenu addItem:NSMenuItem.separatorItem];

            NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
            if (windowItem != nil) {
                windowItem.submenu = windowMenu;
                [appSubmenu addItem:windowItem];
            }
        }
    }

    pixi_menu_bar_set_up = true;
    return true;
}

int PixiMacOSPollPendingNativeMenuAction(void) {
    return atomic_exchange(&pixi_pending_native_menu_action_id, -1);
}

bool PixiMacOSConsumeCloseTabSuppression(void) {
    return atomic_exchange(&pixi_suppress_close_tab_close, false);
}
