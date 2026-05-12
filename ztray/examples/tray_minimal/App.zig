//! Minimal tray-only sample: no window toolkit, no menubar. On Windows a message-only HWND owns the tray icon.
const std = @import("std");
const builtin = @import("builtin");

const ztray = @import("ztray");

const menu_def = @import("menu_def.zig");

pub const std_options = std.Options{
    .log_level = .info,
};

extern fn NSApplicationLoad() void;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    if (builtin.os.tag == .macos) NSApplicationLoad();

    ztray.installTrayIcon(gpa, .{
        .tooltip = "ztray tray example",
        .linux_icon_name = if (builtin.os.tag == .linux) "applications-utilities" else null,
    }) catch |err| {
        std.log.err("installTrayIcon: {s}", .{@errorName(err)});
        return;
    };

    ztray.setTrayMenu(gpa, menu_def.tray_menu) catch |err| {
        std.log.err("setTrayMenu: {s}", .{@errorName(err)});
        ztray.shutdownTray();
        return;
    };

    std.log.info("Tray running. Use the tray icon menu (right-click on Windows).", .{});

    while (true) {
        ztray.pumpTrayEvents();
        if (ztray.pollTrayActionId()) |raw| {
            if (std.enums.fromInt(menu_def.TrayAction, raw)) |action| {
                switch (action) {
                    .hello => std.log.info("Hello from tray", .{}),
                    .quit => {
                        ztray.shutdownTray();
                        return;
                    },
                }
            }
        }
        try io.sleep(.fromMilliseconds(50), .awake);
    }
}
