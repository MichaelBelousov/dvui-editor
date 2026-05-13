//! Shared types for [`window_root.zig`](window_root.zig) (e.g. custom title bar on Windows; frame chrome policy).

pub const TitleBarButton = enum { minimize, maximize, close };

/// How to apply native frame chrome on macOS. On Windows both variants use the same DWM path (`policy` is ignored).
pub const FrameChromePolicy = enum {
    /// macOS: wrap content in `NSVisualEffectView` (blur behind UI). Avoid with system tray (`NSStatusItem`); can abort with Launch Services.
    full_vibrancy,
    /// macOS: transparent title bar + tint without `NSVisualEffectView` (safe with tray).
    tray_compatible,
};
