//! Optional **native window frame** styling: macOS transparent title bar + vibrancy; Windows DWM acrylic + extended caption; Linux X11 (GTK titlebar variant, optional KDE blur) and Wayland (stub).
//! Use [`setFrameChrome`] with [`FrameChromePolicy`]: on macOS, **`.tray_compatible`** avoids `NSVisualEffectView` (safe with `NSStatusItem` / tray); **`.full_vibrancy`** adds blur behind content but can abort with tray on recent macOS. On **Windows**, both policies map to the same DWM path (`policy` is ignored). On **Linux X11**, **`.full_vibrancy`** may set `_KDE_NET_WM_BLUR_BEHIND_REGION` when supported; **`.tray_compatible`** clears it. On **Linux Wayland**, APIs are no-ops until implemented.
//! **`titleBarButtonAt`**, **`performTitleBarButton`**, and **`titleBarButtonWidth`** are implemented on **Windows only** (custom in-client title bar). On macOS they are no-ops / null / 0 — use standard traffic lights or draw outside those APIs.
//!
//! Wire with **`createZwindowModule`** from this package’s `build.zig` and **`addImport("zwindow", …)`**. Not re-exported from [`root.zig`](root.zig).
//!
//! On Windows, `*anyopaque` arguments are native `HWND` (e.g. from SDL `SDL_PROP_WINDOW_WIN32_HWND_POINTER`). On macOS they are `NSWindow *`. On **Linux**, pass **`LinuxFrameTarget`** (see [`LinuxFrameTarget`](window_common.zig)) as `*anyopaque` (e.g. `zwindow.setFrameChrome(@ptrCast(&frame), …)` with `frame` matching `wio.backend.active`).
const builtin = @import("builtin");

const common = @import("window_common.zig");

pub const TitleBarButton = common.TitleBarButton;
pub const FrameChromePolicy = common.FrameChromePolicy;
pub const LinuxX11WindowRef = common.LinuxX11WindowRef;
pub const LinuxWaylandWindowRef = common.LinuxWaylandWindowRef;
pub const LinuxFrameTarget = common.LinuxFrameTarget;

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
    .linux => @import("window_linux.zig"),
    else => struct {
        pub fn applyTransparentTitlebar(_: *anyopaque) void {}
        pub fn setFrameChrome(_: *anyopaque, _: f64, _: f64, _: f64, _: f64, _: bool, _: FrameChromePolicy) void {}
    },
};

const win_impl = switch (builtin.os.tag) {
    .windows => @import("window_windows.zig"),
    else => stub,
};

/// Full-size content view, transparent title bar, and delegate proxy (macOS). On Windows: DWM acrylic-style backdrop and extended client. On Linux: see [`LinuxFrameTarget`].
pub fn applyTransparentTitlebar(native_window: *anyopaque) void {
    impl.applyTransparentTitlebar(native_window);
}

/// Transparent title bar, backdrop/tint, and optional macOS vibrancy per [`FrameChromePolicy`]. On Windows `policy` is ignored. On Linux, `native_window` is `*LinuxFrameTarget` (see module doc).
pub fn setFrameChrome(native_window: *anyopaque, red: f64, green: f64, blue: f64, alpha: f64, dark: bool, policy: FrameChromePolicy) void {
    impl.setFrameChrome(native_window, red, green, blue, alpha, dark, policy);
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
