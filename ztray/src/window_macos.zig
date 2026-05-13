//! macOS AppKit implementation for [`window_root.zig`](window_root.zig).

const common = @import("window_common.zig");

extern fn ZWindowApplyTransparentTitlebar(window: *anyopaque) void;
extern fn ZWindowSetVibrantChrome(window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool) void;
extern fn ZWindowSetTitlebarChromeNoEffectView(window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool) void;

pub fn applyTransparentTitlebar(ns_window: *anyopaque) void {
    ZWindowApplyTransparentTitlebar(ns_window);
}

pub fn setFrameChrome(ns_window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool, policy: common.FrameChromePolicy) void {
    switch (policy) {
        .full_vibrancy => ZWindowSetVibrantChrome(ns_window, red, green, blue, alpha, dark),
        .tray_compatible => ZWindowSetTitlebarChromeNoEffectView(ns_window, red, green, blue, alpha, dark),
    }
}
