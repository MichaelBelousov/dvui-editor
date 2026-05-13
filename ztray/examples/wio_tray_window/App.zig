//! [wio](https://github.com/ypsvlq/wio) window with ztray **native** menubar and **system tray** (icon + menu).
//! On Windows the same top-level `HWND` is used for the menubar and tray callbacks (`windows_hwnd`).
//! **Linux:** pass `zwindow.LinuxFrameTarget` built from `wio.backend.active` and `window.backend`.
const std = @import("std");
const builtin = @import("builtin");

const wio = @import("wio");
const ztray = @import("ztray");
const zwindow = @import("zwindow");

const menu_def = @import("menu_def.zig");

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
            .{ .r = 0.12, .g = 0.13, .b = 0.17, .dark = true },
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
            zwindow.setFrameChrome(@ptrCast(&frame), .{ .r = 0.12, .g = 0.13, .b = 0.17, .dark = true });
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
        .title = "ztray + wio (menus + tray + window chrome)",
        .scale = 1,
        .size = .{ .width = 560, .height = 360 },
    });

    const win_hwnd: ?*anyopaque = if (builtin.os.tag == .windows) @ptrCast(window.backend.window) else null;

    ztray.installMainMenu(gpa, menu_def.menu_bar, .{ .windows_hwnd = win_hwnd }) catch |err| {
        std.log.err("installMainMenu: {s}", .{@errorName(err)});
    };

    ztray.installTrayIcon(gpa, .{
        .tooltip = "ztray wio (menus + tray)",
        .icon_png = if (builtin.os.tag == .linux) null else ztray.zig_favicon_png,
        .linux_icon_name = if (builtin.os.tag == .linux) "applications-utilities" else null,
        .windows_hwnd = win_hwnd,
    }) catch |err| {
        std.log.err("installTrayIcon: {s}", .{@errorName(err)});
        window.destroy();
        wio.deinit();
        return;
    };

    ztray.setTrayMenu(gpa, menu_def.tray_menu) catch |err| {
        std.log.err("setTrayMenu: {s}", .{@errorName(err)});
        ztray.shutdownTray();
        window.destroy();
        wio.deinit();
        return;
    };

    applyZwindowFrameChrome();

    try wio.run(loop);
}

fn loop() !bool {
    while (window.getEvent()) |event| {
        switch (event) {
            .close => {
                ztray.shutdownTray();
                window.destroy();
                wio.deinit();
                return false;
            },
            else => {},
        }
    }

    ztray.pumpEvents();

    if (ztray.pollTrayAction(menu_def.TrayAction)) |action| {
        switch (action) {
            .hello => std.log.info("Hello from tray", .{}),
            .quit => {
                ztray.shutdownTray();
                window.destroy();
                wio.deinit();
                return false;
            },
        }
    }

    if (ztray.pollAction(menu_def.MenuBarAction)) |action| {
        switch (action) {
            .say_hello => std.log.info("Hello from native menu", .{}),
            .about => std.log.info("ztray wio example: shell menu + tray.", .{}),
        }
    }

    wio.wait(.{ .timeout_ns = std.time.ns_per_ms });
    return true;
}
