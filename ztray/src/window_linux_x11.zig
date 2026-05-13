//! X11 frame chrome: GTK titlebar theme variant hint, `_NET_WM_WINDOW_OPACITY` from `alpha`, optional KDE blur region.
//!
//! X11 windows here use server-side decorations from the window manager (wio's path), so there is no real "transparent title bar" toggle to flip; the GTK theme variant hint nudges GNOME/Mutter (and a few others) to pick the dark caption, and `_NET_WM_WINDOW_OPACITY` lets a compositing WM (picom / Mutter / KWin / etc.) draw the entire window translucently. `red` / `green` / `blue` are accepted for API parity with macOS / Windows but X11 has no portable tint hook beyond CSD (`_GTK_FRAME_EXTENTS`), which is out of scope here.

const std = @import("std");
const common = @import("window_common.zig");

const log = std.log.scoped(.zwindow);

const Display = opaque {};
const Window = c_ulong;
const Atom = c_ulong;

const XA_CARDINAL: Atom = 6;

extern fn XInternAtom(?*Display, [*:0]const u8, c_int) callconv(.c) Atom;
extern fn XChangeProperty(?*Display, Window, Atom, Atom, c_int, c_int, ?*const anyopaque, c_int) callconv(.c) c_int;
extern fn XDeleteProperty(?*Display, Window, Atom) callconv(.c) c_int;
extern fn XGetGeometry(
    ?*Display,
    Window,
    *Window,
    *c_int,
    *c_int,
    *c_uint,
    *c_uint,
    *c_uint,
    *c_uint,
) callconv(.c) c_int;
extern fn XFlush(?*Display) callconv(.c) c_int;

fn displayPtr(ref: *const common.LinuxX11WindowRef) *Display {
    return @ptrCast(@alignCast(ref.display));
}

/// Always creates the atom if it does not exist (Xlib `only_if_exists=False`); never returns `None`.
fn internCreate(dpy: *Display, name: [*:0]const u8) Atom {
    return XInternAtom(dpy, name, 0);
}

/// Returns `null` when the atom does not exist on the server (Xlib `only_if_exists=True` returning `None`). Use for compositor-specific atoms like `_KDE_NET_WM_BLUR_BEHIND_REGION` so the call is a no-op on non-supporting WMs.
fn internExisting(dpy: *Display, name: [*:0]const u8) ?Atom {
    const a = XInternAtom(dpy, name, 1);
    return if (a == 0) null else a;
}

fn setUtf8Property(dpy: *Display, win: Window, prop_name: [*:0]const u8, value: []const u8) void {
    const prop = internCreate(dpy, prop_name);
    const utf8 = internCreate(dpy, "UTF8_STRING");
    _ = XChangeProperty(
        dpy,
        win,
        prop,
        utf8,
        8,
        0, // PropModeReplace
        value.ptr,
        @intCast(value.len),
    );
}

fn setCardinalArrayProperty(dpy: *Display, win: Window, prop: Atom, items: []const u32) void {
    _ = XChangeProperty(
        dpy,
        win,
        prop,
        XA_CARDINAL,
        32,
        0, // PropModeReplace
        items.ptr,
        @intCast(items.len),
    );
}

fn applyGtkThemeVariant(ref: *const common.LinuxX11WindowRef, dark: bool) void {
    const dpy = displayPtr(ref);
    const win = ref.window;
    const variant: []const u8 = if (dark) "dark" else "light";
    setUtf8Property(dpy, win, "_GTK_THEME_VARIANT", variant);
}

/// Translates `alpha` (0.0 – 1.0) to `_NET_WM_WINDOW_OPACITY` (`CARDINAL`, full range `0..0xFFFF_FFFF`). When `alpha >= 1.0` the property is deleted so the WM treats the window as fully opaque again.
fn applyWindowOpacity(ref: *const common.LinuxX11WindowRef, alpha: f64) void {
    const dpy = displayPtr(ref);
    const win = ref.window;
    const prop = internCreate(dpy, "_NET_WM_WINDOW_OPACITY");
    if (alpha >= 1.0) {
        _ = XDeleteProperty(dpy, win, prop);
        return;
    }
    const clamped: f64 = if (alpha < 0.0) 0.0 else alpha;
    const opacity: u32 = @intFromFloat(clamped * @as(f64, 0xFFFF_FFFF));
    const items = [_]u32{opacity};
    setCardinalArrayProperty(dpy, win, prop, &items);
}

fn applyKdeBlurIfPresent(ref: *const common.LinuxX11WindowRef) void {
    const dpy = displayPtr(ref);
    const win = ref.window;
    const blur_atom = internExisting(dpy, "_KDE_NET_WM_BLUR_BEHIND_REGION") orelse {
        log.debug("zwindow: _KDE_NET_WM_BLUR_BEHIND_REGION not present (compositor is not KWin)", .{});
        return;
    };

    var root: Window = undefined;
    var x: c_int = undefined;
    var y: c_int = undefined;
    var w: c_uint = undefined;
    var h: c_uint = undefined;
    var border: c_uint = undefined;
    var depth: c_uint = undefined;
    if (XGetGeometry(dpy, win, &root, &x, &y, &w, &h, &border, &depth) == 0) return;

    const rect = [_]u32{ 0, 0, w, h };
    setCardinalArrayProperty(dpy, win, blur_atom, &rect);
}

fn clearKdeBlur(ref: *const common.LinuxX11WindowRef) void {
    const dpy = displayPtr(ref);
    const win = ref.window;
    const blur_atom = internExisting(dpy, "_KDE_NET_WM_BLUR_BEHIND_REGION") orelse return;
    _ = XDeleteProperty(dpy, win, blur_atom);
}

pub fn applyTransparentTitlebar(ref: *const common.LinuxX11WindowRef) void {
    applyGtkThemeVariant(ref, true);
    _ = XFlush(displayPtr(ref));
}

pub fn setFrameChrome(ref: *const common.LinuxX11WindowRef, chrome: common.FrameChrome) void {
    applyGtkThemeVariant(ref, chrome.dark);
    applyWindowOpacity(ref, chrome.a);
    switch (chrome.policy) {
        .full_vibrancy => applyKdeBlurIfPresent(ref),
        .tray_compatible => clearKdeBlur(ref),
    }
    _ = XFlush(displayPtr(ref));
}
