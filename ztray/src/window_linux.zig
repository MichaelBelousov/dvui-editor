//! Linux zwindow: X11 and/or Wayland per `zwindow_build_options`.

const std = @import("std");
const common = @import("window_common.zig");

const build_opts = @import("zwindow_build_options");

const x11_impl = if (build_opts.x11) @import("window_linux_x11.zig") else struct {
    pub fn applyTransparentTitlebar(_: *const common.LinuxX11WindowRef) void {}
    pub fn setFrameChrome(_: *const common.LinuxX11WindowRef, _: f64, _: f64, _: f64, _: f64, _: bool, _: common.FrameChromePolicy) void {}
};

const wl_impl = if (build_opts.wayland) @import("window_linux_wayland.zig") else struct {
    pub fn applyTransparentTitlebar(_: *const common.LinuxWaylandWindowRef) void {}
    pub fn setFrameChrome(_: *const common.LinuxWaylandWindowRef, _: f64, _: f64, _: f64, _: f64, _: bool, _: common.FrameChromePolicy) void {}
};

fn logDisabled(comptime tag: []const u8) void {
    std.log.debug("zwindow: LinuxFrameTarget.{s} not enabled at compile time (-Dzwindow_unix_backends)", .{tag});
}

pub fn applyTransparentTitlebar(native_window: *anyopaque) void {
    const t: *common.LinuxFrameTarget = @ptrCast(@alignCast(native_window));
    switch (t.*) {
        .x11 => {
            if (build_opts.x11) {
                x11_impl.applyTransparentTitlebar(&t.x11);
            } else {
                logDisabled("x11");
            }
        },
        .wayland => {
            if (build_opts.wayland) {
                wl_impl.applyTransparentTitlebar(&t.wayland);
            } else {
                logDisabled("wayland");
            }
        },
    }
}

pub fn setFrameChrome(
    native_window: *anyopaque,
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
    dark: bool,
    policy: common.FrameChromePolicy,
) void {
    const t: *common.LinuxFrameTarget = @ptrCast(@alignCast(native_window));
    switch (t.*) {
        .x11 => {
            if (build_opts.x11) {
                x11_impl.setFrameChrome(&t.x11, red, green, blue, alpha, dark, policy);
            } else {
                logDisabled("x11");
            }
        },
        .wayland => {
            if (build_opts.wayland) {
                wl_impl.setFrameChrome(&t.wayland, red, green, blue, alpha, dark, policy);
            } else {
                logDisabled("wayland");
            }
        },
    }
}
