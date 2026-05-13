//! Minimal tray-only sample: no window toolkit, no menubar. On Windows a message-only HWND owns the tray icon.
//! The favicon PNG is embedded in the `ztray` package as `ztray.zig_favicon_png`; macOS/Windows use
//! `TrayIconOptions.icon_png`. Linux SNI uses `linux_icon_name` (embedded PNG is not wired for pixmap icons yet).
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

    ztray.installTrayIcon(gpa, ztray.trayIcon(
        "ztray tray example",
        ztray.zig_favicon_png,
        "applications-utilities",
    )) catch |err| {
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
        ztray.pumpEvents();
        if (ztray.pollTrayAction(menu_def.TrayAction)) |action| {
            switch (action) {
                .hello => std.log.info("Hello from tray", .{}),
                .quit => {
                    ztray.shutdownTray();
                    return;
                },
            }
        }
        try io.sleep(.fromMilliseconds(50), .awake);
    }
}
