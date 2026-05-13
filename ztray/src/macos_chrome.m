#import <AppKit/AppKit.h>
#include <stdbool.h>
#import <objc/runtime.h>

static const NSUInteger ZChromeFullSizeContentViewMask = 1u << 15;
static const NSVisualEffectMaterial ZChromeVisualEffectMaterial = 15;
static const void *ZChromeWindowDelegateProxyAssociationKey = &ZChromeWindowDelegateProxyAssociationKey;

@interface ZChromeVisualEffectView : NSVisualEffectView
@end

@implementation ZChromeVisualEffectView
- (void)rightMouseDown:(NSEvent *)event {
    NSView *contentView = self.subviews.firstObject;
    if (contentView != nil) {
        [contentView rightMouseDown:event];
        return;
    }
    [super rightMouseDown:event];
}
@end

@interface ZChromeWindowDelegateProxy : NSObject <NSWindowDelegate>
@property (nonatomic, assign) id<NSWindowDelegate> originalDelegate;
@property (nonatomic, assign) BOOL suppressNextWindowClose;
- (instancetype)initWithOriginalDelegate:(id<NSWindowDelegate>)originalDelegate;
@end

@implementation ZChromeWindowDelegateProxy
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

static void zchromeWrapContentViewWithVibrancy(NSWindow *window) {
    NSView *contentView = window.contentView;
    if (contentView == nil) return;

    const NSUInteger fillMask = NSViewWidthSizable | NSViewHeightSizable;
    if ([contentView isKindOfClass:[NSVisualEffectView class]]) {
        NSVisualEffectView *effectView = (NSVisualEffectView *)contentView;
        effectView.material = ZChromeVisualEffectMaterial;
        effectView.menu = nil;
        NSView *subview = effectView.subviews.firstObject;
        if (subview != nil && window.delegate != nil) {
            subview.nextResponder = (NSResponder *)window.delegate;
        }
        return;
    }

    ZChromeVisualEffectView *effectView = [[ZChromeVisualEffectView alloc] init];
    if (effectView == nil) return;

    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.state = NSVisualEffectStateActive;
    effectView.material = ZChromeVisualEffectMaterial;
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

static ZChromeWindowDelegateProxy *zchromeInstallWindowDelegateProxy(NSWindow *window) {
    if (window == nil) return nil;

    ZChromeWindowDelegateProxy *proxy = objc_getAssociatedObject(window, ZChromeWindowDelegateProxyAssociationKey);
    if (proxy != nil) return proxy;

    id<NSWindowDelegate> originalDelegate = window.delegate;
    if ([originalDelegate isKindOfClass:[ZChromeWindowDelegateProxy class]]) {
        return (ZChromeWindowDelegateProxy *)originalDelegate;
    }

    proxy = [[ZChromeWindowDelegateProxy alloc] initWithOriginalDelegate:originalDelegate];
    if (proxy == nil) return nil;

    objc_setAssociatedObject(window, ZChromeWindowDelegateProxyAssociationKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.delegate = proxy;
    return proxy;
}

void ZChromeApplyTransparentTitlebar(void *window_ptr) {
    NSWindow *window = (__bridge NSWindow *)window_ptr;
    if (window == nil) return;

    zchromeInstallWindowDelegateProxy(window);
    window.styleMask |= ZChromeFullSizeContentViewMask;
    window.titlebarAppearsTransparent = YES;
}

void ZChromeSetVibrantChrome(void *window_ptr, double red, double green, double blue, double alpha, bool dark) {
    NSWindow *window = (__bridge NSWindow *)window_ptr;
    if (window == nil) return;

    ZChromeApplyTransparentTitlebar(window_ptr);
    zchromeWrapContentViewWithVibrancy(window);

    window.backgroundColor = [NSColor colorWithRed:red green:green blue:blue alpha:alpha];
    window.appearance = [NSAppearance appearanceNamed:(dark ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)];
    window.hasShadow = YES;
}
