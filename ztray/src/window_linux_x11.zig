//! X11 frame chrome: GTK titlebar theme hint, optional KDE blur region.

const std = @import("std");
const common = @import("window_common.zig");

const Display = opaque {};
const Window = c_ulong;
const Atom = c_ulong;

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

fn intern(dpy: *Display, name: [*:0]const u8) Atom {
    return XInternAtom(dpy, name, 0);
}

fn setUtf8Property(dpy: *Display, win: Window, prop_name: [*:0]const u8, value: []const u8) void {
    const prop = intern(dpy, prop_name);
    const utf8 = intern(dpy, "UTF8_STRING");
    if (prop == 0 or utf8 == 0) return;
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

fn setCardinalArrayProperty(dpy: *Display, win: Window, prop_name: [*:0]const u8, items: []const u32) void {
    const prop = intern(dpy, prop_name);
    if (prop == 0) return;
    const xa_cardinal = intern(dpy, "CARDINAL");
    if (xa_cardinal == 0) return;
    _ = XChangeProperty(
        dpy,
        win,
        prop,
        xa_cardinal,
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

fn applyKdeBlurIfPresent(ref: *const common.LinuxX11WindowRef) void {
    const dpy = displayPtr(ref);
    const win = ref.window;
    const blur_atom = intern(dpy, "_KDE_NET_WM_BLUR_BEHIND_REGION");
    if (blur_atom == 0) return;

    var root: Window = undefined;
    var x: c_int = undefined;
    var y: c_int = undefined;
    var w: c_uint = undefined;
    var h: c_uint = undefined;
    var border: c_uint = undefined;
    var depth: c_uint = undefined;
    if (XGetGeometry(dpy, win, &root, &x, &y, &w, &h, &border, &depth) == 0) return;

    const rect = [_]u32{ 0, 0, w, h };
    setCardinalArrayProperty(dpy, win, "_KDE_NET_WM_BLUR_BEHIND_REGION", &rect);
}

fn clearKdeBlur(ref: *const common.LinuxX11WindowRef) void {
    const dpy = displayPtr(ref);
    const win = ref.window;
    const blur_atom = intern(dpy, "_KDE_NET_WM_BLUR_BEHIND_REGION");
    if (blur_atom == 0) return;
    _ = XDeleteProperty(dpy, win, blur_atom);
}

pub fn applyTransparentTitlebar(ref: *const common.LinuxX11WindowRef) void {
    applyGtkThemeVariant(ref, true);
    _ = XFlush(displayPtr(ref));
}

pub fn setFrameChrome(
    ref: *const common.LinuxX11WindowRef,
    _: f64,
    _: f64,
    _: f64,
    _: f64,
    dark: bool,
    policy: common.FrameChromePolicy,
) void {
    applyGtkThemeVariant(ref, dark);
    switch (policy) {
        .full_vibrancy => applyKdeBlurIfPresent(ref),
        .tray_compatible => clearKdeBlur(ref),
    }
    _ = XFlush(displayPtr(ref));
}
