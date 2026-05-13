#import <AppKit/AppKit.h>
#include <stdbool.h>
#import <objc/runtime.h>

static const NSUInteger ZWindowFullSizeContentViewMask = 1u << 15;
static const NSVisualEffectMaterial ZWindowVisualEffectMaterial = 15;
static const void *ZWindowDelegateProxyAssociationKey = &ZWindowDelegateProxyAssociationKey;

@interface ZWindowVisualEffectView : NSVisualEffectView
@end

@implementation ZWindowVisualEffectView
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
            subview.nextResponder = (NSResponder *)window.delegate;
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
        contentView.nextResponder = (NSResponder *)window.delegate;
    }
    contentView.frame = effectView.bounds;
    contentView.autoresizingMask = fillMask;
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
