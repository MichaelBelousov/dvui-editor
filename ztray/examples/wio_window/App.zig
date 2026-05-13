//! [wio](https://github.com/ypsvlq/wio) window + **zwindow** only (no ztray menu or tray).
//! On Linux: `zwindow.LinuxFrameTarget` from `wio.backend` + `window.backend`.
const std = @import("std");
const builtin = @import("builtin");

const wio = @import("wio");
const zwindow = @import("zwindow");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = wio.logFn,
};

comptime {
    _ = wio;
}

extern fn NSApplicationLoad() void;

var window: wio.Window = undefined;

fn applyZwindowFrameChrome() void {
    switch (builtin.os.tag) {
        .windows, .macos => zwindow.setFrameChrome(
            @ptrCast(window.backend.window),
            0.18, 0.19, 0.24, 1.0, true, .full_vibrancy,
        ),
        .linux => {
            var frame = switch (wio.backend.active) {
                .x11 => zwindow.LinuxFrameTarget.fromX11(
                    @ptrCast(wio.backend.x11.display),
                    window.backend.x11.window,
                ),
                .wayland => zwindow.LinuxFrameTarget.fromWayland(
                    @ptrCast(wio.backend.wayland.display),
                    @ptrCast(window.backend.wayland.surface),
                ),
            };
            zwindow.setFrameChrome(@ptrCast(&frame), 0.18, 0.19, 0.24, 1.0, true, .full_vibrancy);
        },
        else => {},
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    try wio.init(gpa, io, .{});

    if (builtin.os.tag == .macos) NSApplicationLoad();

    window = try wio.createWindow(.{
        .title = "zwindow + wio",
        .scale = 1,
        .size = .{ .width = 520, .height = 340 },
    });

    applyZwindowFrameChrome();

    try wio.run(loop);
}

fn loop() !bool {
    while (window.getEvent()) |event| {
        switch (event) {
            .close => {
                window.destroy();
                wio.deinit();
                return false;
            },
            else => {},
        }
    }

    wio.wait(.{ .timeout_ns = std.time.ns_per_ms });
    return true;
}
