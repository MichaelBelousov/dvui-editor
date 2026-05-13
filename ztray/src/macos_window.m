#import <AppKit/AppKit.h>
#include <stdbool.h>
#import <objc/runtime.h>

static const NSUInteger ZWindowFullSizeContentViewMask = 1u << 15;
static const NSVisualEffectMaterial ZWindowVisualEffectMaterial = 15;
static const void *ZWindowDelegateProxyAssociationKey = &ZWindowDelegateProxyAssociationKey;

@interface ZWindowVisualEffectView : NSVisualEffectView
@end

@implementation ZWindowVisualEffectView

/// Real client view (e.g. wio `WioView`) after vibrancy wrap; `NSWindow` APIs still expose this wrapper as `contentView`.
- (NSView *)zwindowInnerClientView {
    return self.subviews.firstObject;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    NSView *inner = [self zwindowInnerClientView];
    if (inner != nil && [inner respondsToSelector:aSelector]) return YES;
    return [super respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    NSView *inner = [self zwindowInnerClientView];
    if (inner != nil && [inner respondsToSelector:aSelector]) return inner;
    return [super forwardingTargetForSelector:aSelector];
}

- (void)updateTrackingAreas {
    NSView *inner = [self zwindowInnerClientView];
    if (inner != nil) [inner updateTrackingAreas];
    [super updateTrackingAreas];
}

- (void)rightMouseDown:(NSEvent *)event {
    NSView *contentView = self.subviews.firstObject;
    if (contentView != nil) {
        [contentView rightMouseDown:event];
        return;
    }
    [super rightMouseDown:event];
}
@end

@interface ZWindowDelegateProxy : NSObject <NSWindowDelegate>
@property (nonatomic, assign) id<NSWindowDelegate> originalDelegate;
@property (nonatomic, assign) BOOL suppressNextWindowClose;
- (instancetype)initWithOriginalDelegate:(id<NSWindowDelegate>)originalDelegate;
@end

@implementation ZWindowDelegateProxy
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

/// `NSWindow.delegate` is often `ZWindowDelegateProxy` (NSObject), which must not be passed to `-[NSView setNextResponder:]`.
static void zwindowSetInnerContentNextResponder(NSWindow *window, NSView *innerContent) {
    id del = window.delegate;
    if (del == nil) return;
    NSResponder *target = nil;
    if ([del isKindOfClass:[NSResponder class]]) {
        target = (NSResponder *)del;
    } else {
        target = window;
    }
    innerContent.nextResponder = target;
}

static void zwindowWrapContentViewWithVibrancy(NSWindow *window) {
    NSView *contentView = window.contentView;
    if (contentView == nil) return;

    const NSUInteger fillMask = NSViewWidthSizable | NSViewHeightSizable;
    if ([contentView isKindOfClass:[NSVisualEffectView class]]) {
        NSVisualEffectView *effectView = (NSVisualEffectView *)contentView;
        effectView.material = ZWindowVisualEffectMaterial;
        effectView.menu = nil;
        NSView *subview = effectView.subviews.firstObject;
        if (subview != nil && window.delegate != nil) {
            zwindowSetInnerContentNextResponder(window, subview);
        }
        return;
    }

    ZWindowVisualEffectView *effectView = [[ZWindowVisualEffectView alloc] init];
    if (effectView == nil) return;

    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.state = NSVisualEffectStateActive;
    effectView.material = ZWindowVisualEffectMaterial;
    effectView.menu = nil;

    [window setContentView:effectView];
    [effectView addSubview:contentView];
    contentView.menu = nil;
    if (window.delegate != nil) {
        zwindowSetInnerContentNextResponder(window, contentView);
    }
    contentView.frame = effectView.bounds;
    contentView.autoresizingMask = fillMask;
    [window makeFirstResponder:contentView];
}

static ZWindowDelegateProxy *zwindowInstallWindowDelegateProxy(NSWindow *window) {
    if (window == nil) return nil;

    ZWindowDelegateProxy *proxy = objc_getAssociatedObject(window, ZWindowDelegateProxyAssociationKey);
    if (proxy != nil) return proxy;

    id<NSWindowDelegate> originalDelegate = window.delegate;
    if ([originalDelegate isKindOfClass:[ZWindowDelegateProxy class]]) {
        return (ZWindowDelegateProxy *)originalDelegate;
    }

    proxy = [[ZWindowDelegateProxy alloc] initWithOriginalDelegate:originalDelegate];
    if (proxy == nil) return nil;

    objc_setAssociatedObject(window, ZWindowDelegateProxyAssociationKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.delegate = proxy;
    return proxy;
}

void ZWindowApplyTransparentTitlebar(void *window_ptr) {
    NSWindow *window = (__bridge NSWindow *)window_ptr;
    if (window == nil) return;

    zwindowInstallWindowDelegateProxy(window);
    window.styleMask |= ZWindowFullSizeContentViewMask;
    window.titlebarAppearsTransparent = YES;
}

void ZWindowSetVibrantChrome(void *window_ptr, double red, double green, double blue, double alpha, bool dark) {
    NSWindow *window = (__bridge NSWindow *)window_ptr;
    if (window == nil) return;

    ZWindowApplyTransparentTitlebar(window_ptr);
    zwindowWrapContentViewWithVibrancy(window);

    window.backgroundColor = [NSColor colorWithRed:red green:green blue:blue alpha:alpha];
    window.appearance = [NSAppearance appearanceNamed:(dark ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)];
    window.hasShadow = YES;
}

/// Same title bar + tint/appearance as [`ZWindowSetVibrantChrome`] but does **not** wrap the content view in `NSVisualEffectView`.
/// Use with `NSStatusItem` (e.g. ztray tray): full vibrancy can abort in Launch Services on recent macOS.
void ZWindowSetTitlebarChromeNoEffectView(void *window_ptr, double red, double green, double blue, double alpha, bool dark) {
    NSWindow *window = (__bridge NSWindow *)window_ptr;
    if (window == nil) return;

    ZWindowApplyTransparentTitlebar(window_ptr);
    window.backgroundColor = [NSColor colorWithRed:red green:green blue:blue alpha:alpha];
    window.appearance = [NSAppearance appearanceNamed:(dark ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)];
    window.hasShadow = YES;
}
