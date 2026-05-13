//! macOS AppKit implementation for [`window_root.zig`](window_root.zig).

extern fn ZWindowApplyTransparentTitlebar(window: *anyopaque) void;
extern fn ZWindowSetVibrantChrome(window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool) void;

pub fn applyTransparentTitlebar(ns_window: *anyopaque) void {
    ZWindowApplyTransparentTitlebar(ns_window);
}

pub fn setVibrantChrome(ns_window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool) void {
    ZWindowSetVibrantChrome(ns_window, red, green, blue, alpha, dark);
}
