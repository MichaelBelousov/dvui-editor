//! Shared types for [`window_root.zig`](window_root.zig) (e.g. custom title bar on Windows; frame chrome policy).

/// X11: `display` is `Display *`, `window` is the X11 `Window` id (e.g. from wio `backend.x11.window` with `wio.backend.x11.display`).
pub const LinuxX11WindowRef = extern struct {
    display: *anyopaque,
    window: c_ulong,
};

/// Wayland: `display` is the `wl_display *` (e.g. `wio.backend.wayland.display`); `surface` is the `wl_surface *` (e.g. `window.backend.wayland.surface`). zwindow `dlopen`s `libwayland-client.so.0` at runtime, so consumers do not need to link Wayland.
pub const LinuxWaylandWindowRef = extern struct {
    display: *anyopaque,
    surface: *anyopaque,
};

/// Linux: pass `*LinuxFrameTarget` as `*anyopaque` to [`setFrameChrome`](window_root.zig) / [`applyTransparentTitlebar`](window_root.zig). Match [`wio.backend.active`](https://github.com/ypsvlq/wio) to the union tag.
pub const LinuxFrameTarget = union(enum) {
    x11: LinuxX11WindowRef,
    wayland: LinuxWaylandWindowRef,

    pub fn fromX11(display: *anyopaque, window: c_ulong) LinuxFrameTarget {
        return .{ .x11 = .{ .display = display, .window = window } };
    }

    pub fn fromWayland(display: *anyopaque, surface: *anyopaque) LinuxFrameTarget {
        return .{ .wayland = .{ .display = display, .surface = surface } };
    }
};

pub const TitleBarButton = enum { minimize, maximize, close };

/// How to apply native frame chrome on macOS. On Windows both variants use the same DWM path (`policy` is ignored).
pub const FrameChromePolicy = enum {
    /// macOS: wrap content in `NSVisualEffectView` (blur behind UI). Avoid with system tray (`NSStatusItem`); can abort with Launch Services.
    full_vibrancy,
    /// macOS: transparent title bar + tint without `NSVisualEffectView` (safe with tray).
    tray_compatible,
};

/// Options for [`setFrameChrome`](window_root.zig). All fields have safe defaults (black, opaque, not dark, tray-safe).
pub const FrameChrome = struct {
    r: f64 = 0.0,
    g: f64 = 0.0,
    b: f64 = 0.0,
    a: f64 = 1.0,
    dark: bool = false,
    policy: FrameChromePolicy = .tray_compatible,
};
