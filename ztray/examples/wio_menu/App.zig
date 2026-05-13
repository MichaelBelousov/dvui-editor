//! Minimal [wio](https://github.com/ypsvlq/wio) window using ztray **native** menus (no DVUI fallback).
const std = @import("std");
const builtin = @import("builtin");

const wio = @import("wio");
const ztray = @import("ztray");

const menu_def = @import("menu_def.zig");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = wio.logFn,
};

comptime {
    _ = wio;
}

var window: wio.Window = undefined;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    try wio.init(gpa, io, .{});

    window = try wio.createWindow(.{
        .title = "ztray + wio (native menus)",
        .scale = 1,
        .size = .{ .width = 560, .height = 360 },
    });

    ztray.installMainMenu(gpa, menu_def.menu_bar, .{
        .windows_hwnd = if (builtin.os.tag == .windows) @ptrCast(window.backend.window) else null,
    }) catch |err| {
        std.log.err("installMainMenu: {s}", .{@errorName(err)});
    };

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

    if (ztray.pollAction(menu_def.DemoAction)) |action| {
        switch (action) {
            .say_hello => std.log.info("Hello from native menu", .{}),
            .about => std.log.info("ztray native menu example using wio.", .{}),
        }
    }

    wio.wait(.{ .timeout_ns = std.time.ns_per_ms });
    return true;
}
