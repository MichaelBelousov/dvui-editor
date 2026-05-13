//! [wio](https://github.com/ypsvlq/wio) window + **zchrome** only (no ztray menu or tray).
//! On macOS: transparent title bar and vibrancy via `zchrome`. Other platforms: plain wio window (chrome APIs no-op).
const std = @import("std");
const builtin = @import("builtin");

const wio = @import("wio");
const zchrome = @import("zchrome");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = wio.logFn,
};

comptime {
    _ = wio;
}

extern fn NSApplicationLoad() void;

var window: wio.Window = undefined;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    try wio.init(gpa, io, .{});

    if (builtin.os.tag == .macos) NSApplicationLoad();

    window = try wio.createWindow(.{
        .title = "zchrome + wio",
        .scale = 1,
        .size = .{ .width = 520, .height = 340 },
    });

    if (builtin.os.tag == .macos) {
        const ns: *anyopaque = @ptrCast(window.backend.window);
        zchrome.applyTransparentTitlebar(ns);
        zchrome.setVibrantChrome(ns, 0.18, 0.19, 0.24, 1.0, true);
    }

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
