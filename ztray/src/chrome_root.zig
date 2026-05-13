//! Optional **window chrome** (macOS transparent title bar + vibrancy). Independent of ztray menu and tray.
//!
//! Wire with `createZchromeModule` from this package’s `build.zig` and `addImport("zchrome", …)`. Not re-exported from [`root.zig`](root.zig).
const builtin = @import("builtin");

const impl = switch (builtin.os.tag) {
    .macos => @import("chrome_macos.zig"),
    else => struct {
        pub fn applyTransparentTitlebar(_: *anyopaque) void {}
        pub fn setVibrantChrome(_: *anyopaque, _: f64, _: f64, _: f64, _: f64, _: bool) void {}
    },
};

/// Full-size content view, transparent title bar, and delegate proxy (for optional close suppression flows).
pub fn applyTransparentTitlebar(ns_window: *anyopaque) void {
    impl.applyTransparentTitlebar(ns_window);
}

/// Applies [`applyTransparentTitlebar`] then wraps the content view in a vibrancy material, tint, and light/dark appearance.
pub fn setVibrantChrome(ns_window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool) void {
    impl.setVibrantChrome(ns_window, red, green, blue, alpha, dark);
}
