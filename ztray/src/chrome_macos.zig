//! macOS AppKit implementation for [`chrome_root.zig`](chrome_root.zig).

extern fn ZChromeApplyTransparentTitlebar(window: *anyopaque) void;
extern fn ZChromeSetVibrantChrome(window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool) void;

pub fn applyTransparentTitlebar(ns_window: *anyopaque) void {
    ZChromeApplyTransparentTitlebar(ns_window);
}

pub fn setVibrantChrome(ns_window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool) void {
    ZChromeSetVibrantChrome(ns_window, red, green, blue, alpha, dark);
}
