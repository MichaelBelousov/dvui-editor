//! Optional **native window frame** styling: macOS transparent title bar + vibrancy; Windows DWM acrylic + extended caption.
//! **`titleBarButtonAt`**, **`performTitleBarButton`**, and **`titleBarButtonWidth`** are implemented on **Windows only** (custom in-client title bar). On macOS they are no-ops / null / 0 — use standard traffic lights or draw outside those APIs. On **Linux** and other targets, all entry points are no-ops (no Wayland/X11 client-side decoration here).
//!
//! Wire with **`createZwindowModule`** from this package’s `build.zig` and **`addImport("zwindow", …)`**. Not re-exported from [`root.zig`](root.zig).
//!
//! On Windows, `*anyopaque` arguments are native `HWND` (e.g. from SDL `SDL_PROP_WINDOW_WIN32_HWND_POINTER`). On macOS they are `NSWindow *`.
const builtin = @import("builtin");

pub const TitleBarButton = @import("window_common.zig").TitleBarButton;

const stub = struct {
    pub fn titleBarButtonAt(_: *anyopaque, _: i32, _: i32) ?TitleBarButton {
        return null;
    }
    pub fn performTitleBarButton(_: *anyopaque, _: TitleBarButton) void {}
    pub fn titleBarButtonWidth() i32 {
        return 0;
    }
};

const impl = switch (builtin.os.tag) {
    .macos => @import("window_macos.zig"),
    .windows => @import("window_windows.zig"),
    else => struct {
        pub fn applyTransparentTitlebar(_: *anyopaque) void {}
        pub fn setVibrantChrome(_: *anyopaque, _: f64, _: f64, _: f64, _: f64, _: bool) void {}
    },
};

const win_impl = switch (builtin.os.tag) {
    .windows => @import("window_windows.zig"),
    else => stub,
};

/// Full-size content view, transparent title bar, and delegate proxy (macOS). On Windows: DWM acrylic-style backdrop and extended client.
pub fn applyTransparentTitlebar(native_window: *anyopaque) void {
    impl.applyTransparentTitlebar(native_window);
}

/// macOS: applies [`applyTransparentTitlebar`] then vibrancy material. Windows: reapplies backdrop and clears caption tint; RGBA/dark ignored (opaque window for SDL).
pub fn setVibrantChrome(native_window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool) void {
    impl.setVibrantChrome(native_window, red, green, blue, alpha, dark);
}

/// Custom title bar: which OS caption button (if any) is at client coordinates. Windows only; other platforms return null.
pub fn titleBarButtonAt(native_window: *anyopaque, client_x: i32, client_y: i32) ?TitleBarButton {
    return win_impl.titleBarButtonAt(native_window, client_x, client_y);
}

/// Forward minimize / maximize-restore / close for a custom-drawn title bar. Windows only.
pub fn performTitleBarButton(native_window: *anyopaque, button: TitleBarButton) void {
    win_impl.performTitleBarButton(native_window, button);
}

/// Caption button width in pixels (layout). Windows only; returns 0 elsewhere.
pub fn titleBarButtonWidth() i32 {
    return win_impl.titleBarButtonWidth();
}
