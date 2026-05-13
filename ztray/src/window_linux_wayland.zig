//! Wayland frame chrome for zwindow (stub). Real blur / CSD protocols TBD.

const std = @import("std");
const common = @import("window_common.zig");

pub fn applyTransparentTitlebar(_: *const common.LinuxWaylandWindowRef) void {}

pub fn setFrameChrome(
    _: *const common.LinuxWaylandWindowRef,
    _: f64,
    _: f64,
    _: f64,
    _: f64,
    _: bool,
    _: common.FrameChromePolicy,
) void {
    std.log.debug("zwindow: Wayland setFrameChrome is not implemented yet", .{});
}
