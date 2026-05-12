//! Minimal DVUI app that uses ztray with compile-time forced DVUI menu (`zig build run-ztray-dvui-fallback`).
const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;

const ztray = @import("ztray");
const menu_def = @import("menu_def.zig");

var hello_count: u32 = 0;

pub const dvui_app: dvui.App = .{ .config = .{ .options = .{
    .size = .{ .w = 720.0, .h = 480.0 },
    .min_size = .{ .w = 400.0, .h = 300.0 },
    .title = "ztray DVUI fallback",
    .transparent = if (builtin.os.tag == .macos or builtin.os.tag == .windows) true else false,
} }, .frameFn = AppFrame, .initFn = AppInit, .deinitFn = AppDeinit };

pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

pub fn AppInit(win: *dvui.Window) !void {
    ztray.installMainMenu(win.gpa, menu_def.menu_bar, null) catch |err| {
        std.log.err("ztray installMainMenu: {s}", .{@errorName(err)});
    };
}

pub fn AppDeinit() void {
    ztray.shutdownDvuiMenu();
}

pub fn AppFrame() !dvui.App.Result {
    try ztray.drawMenuBar();

    if (ztray.pollActionId()) |raw| {
        if (std.enums.fromInt(menu_def.DemoAction, raw)) |action| {
            switch (action) {
                .say_hello => {
                    hello_count += 1;
                    std.log.info("Hello from ztray DVUI fallback (#{d})", .{hello_count});
                },
                .toggle_demo => {
                    dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
                },
                .quit_hint => {
                    std.log.info("Use the window close button or platform shortcut to quit.", .{});
                },
            }
        }
    }

    var box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
    defer box.deinit();

    dvui.labelNoFmt(@src(), "Compile this example with:\n  zig build run-ztray-dvui-fallback\n\nMenu bar above uses ztray + DVUI only (no native shell menus).", .{}, .{ .expand = .horizontal });

    dvui.Examples.demo(.lite);

    return .ok;
}
