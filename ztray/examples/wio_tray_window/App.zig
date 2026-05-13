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

fn menuHostHandle(win: *wio.Window) ?*anyopaque {
    return switch (builtin.os.tag) {
        .windows => @ptrCast(win.backend.window),
        else => null,
    };
}

fn applyZwindowFrameChrome() void {
    switch (builtin.os.tag) {
        .windows => {
            const native: *anyopaque = @ptrCast(window.backend.window);
            zwindow.setFrameChrome(
                native,
                0.12,
                0.13,
                0.17,
                1.0,
                true,
                .tray_compatible,
            );
        },
        .macos => {
            const native: *anyopaque = @ptrCast(window.backend.window);
            zwindow.setFrameChrome(
                native,
                0.12,
                0.13,
                0.17,
                1.0,
                true,
                .tray_compatible,
            );
        },
        .linux => {
            switch (wio.backend.active) {
                .x11 => {
                    var frame = zwindow.LinuxFrameTarget{ .x11 = .{
                        .display = @ptrCast(wio.backend.x11.display),
                        .window = window.backend.x11.window,
                    } };
                    zwindow.setFrameChrome(
                        @ptrCast(&frame),
                        0.12,
                        0.13,
                        0.17,
                        1.0,
                        true,
                        .tray_compatible,
                    );
                },
                .wayland => {
                    var frame = zwindow.LinuxFrameTarget{ .wayland = .{
                        .surface = @ptrCast(window.backend.wayland),
                    } };
                    zwindow.setFrameChrome(
                        @ptrCast(&frame),
                        0.12,
                        0.13,
                        0.17,
                        1.0,
                        true,
                        .tray_compatible,
                    );
                },
            }
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

    ztray.installMainMenu(gpa, menu_def.menu_bar, menuHostHandle(&window)) catch |err| {
        std.log.err("installMainMenu: {s}", .{@errorName(err)});
    };

    ztray.installTrayIcon(gpa, .{
        .tooltip = "ztray wio (menus + tray)",
        .icon_png = if (builtin.os.tag == .linux) null else ztray.zig_favicon_png,
        .linux_icon_name = if (builtin.os.tag == .linux) "applications-utilities" else null,
        .windows_hwnd = menuHostHandle(&window),
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

    ztray.pumpTrayEvents();

    if (ztray.pollTrayActionId()) |raw| {
        if (std.enums.fromInt(menu_def.TrayAction, raw)) |action| {
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
    }

    if (ztray.pollActionId()) |raw| {
        if (std.enums.fromInt(menu_def.MenuBarAction, raw)) |action| {
            switch (action) {
                .say_hello => std.log.info("Hello from native menu", .{}),
                .about => std.log.info("ztray wio example: shell menu + tray.", .{}),
            }
        }
    }

    wio.wait(.{ .timeout_ns = std.time.ns_per_ms });
    return true;
}
