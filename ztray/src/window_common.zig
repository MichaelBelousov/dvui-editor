//! Shared types for [`window_root.zig`](window_root.zig) (e.g. custom title bar on Windows; frame chrome policy).

/// X11: `display` is `Display *`, `window` is the X11 `Window` id (e.g. from wio `backend.x11.window` with `wio.backend.x11.display`).
pub const LinuxX11WindowRef = extern struct {
    display: *anyopaque,
    window: c_ulong,
};

/// Wayland: reserved for future use (e.g. `wl_surface *`). Stub implementation ignores fields.
pub const LinuxWaylandWindowRef = extern struct {
    surface: *anyopaque,
};

/// Linux: pass `*LinuxFrameTarget` as `*anyopaque` to [`setFrameChrome`](window_root.zig) / [`applyTransparentTitlebar`](window_root.zig). Match [`wio.backend.active`](https://github.com/ypsvlq/wio) to the union tag.
pub const LinuxFrameTarget = union(enum) {
    x11: LinuxX11WindowRef,
    wayland: LinuxWaylandWindowRef,
};

pub const TitleBarButton = enum { minimize, maximize, close };

/// How to apply native frame chrome on macOS. On Windows both variants use the same DWM path (`policy` is ignored).
pub const FrameChromePolicy = enum {
    /// macOS: wrap content in `NSVisualEffectView` (blur behind UI). Avoid with system tray (`NSStatusItem`); can abort with Launch Services.
    full_vibrancy,
    /// macOS: transparent title bar + tint without `NSVisualEffectView` (safe with tray).
    tray_compatible,
};
