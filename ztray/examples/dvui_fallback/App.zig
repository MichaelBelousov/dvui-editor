//! DVUI app + ztray: **native** shell menu by default; in-app DVUI menu bar with `-Dforce_dvui_menu=true` in this package’s `zig build`.
const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
const sdl3 = @import("sdl-backend").c;
const zopts = @import("ztray_dvui_opts");
const ztray = @import("ztray");
const ztray_dvui = @import("ztray_dvui");

const menu_def = @import("menu_def.zig");

var hello_count: u32 = 0;

fn menuHostHwnd(win: *dvui.Window) ?*anyopaque {
    if (builtin.os.tag != .windows) return null;
    const raw = sdl3.SDL_GetPointerProperty(
        sdl3.SDL_GetWindowProperties(win.backend.impl.window),
        sdl3.SDL_PROP_WINDOW_WIN32_HWND_POINTER,
        null,
    );
    return if (raw != null) @ptrCast(raw) else null;
}

pub const dvui_app: dvui.App = .{ .config = .{ .options = .{
    .size = .{ .w = 720.0, .h = 480.0 },
    .min_size = .{ .w = 400.0, .h = 300.0 },
    .title = if (zopts.force_dvui_menu)
        "ztray + DVUI (in-app menu)"
    else
        "ztray + DVUI (native menu)",
    .transparent = if (builtin.os.tag == .macos or builtin.os.tag == .windows) true else false,
} }, .frameFn = AppFrame, .initFn = AppInit, .deinitFn = AppDeinit };

pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

pub fn AppInit(win: *dvui.Window) !void {
    if (zopts.force_dvui_menu) {
        ztray_dvui.installMainMenu(win.gpa, menu_def.menu_bar) catch |err| {
            std.log.err("ztray_dvui installMainMenu: {s}", .{@errorName(err)});
        };
    } else {
        ztray.installMainMenu(win.gpa, menu_def.menu_bar, menuHostHwnd(win)) catch |err| {
            std.log.err("ztray installMainMenu: {s}", .{@errorName(err)});
        };
    }
}

pub fn AppDeinit() void {
    if (zopts.force_dvui_menu) {
        ztray_dvui.shutdownMenu();
    }
}

pub fn AppFrame() !dvui.App.Result {
    if (zopts.force_dvui_menu) {
        try ztray_dvui.drawMenuBar();
    }

    if (builtin.os.tag == .macos and !zopts.force_dvui_menu) {
        const suppress_close = ztray.consumeCloseTabSuppression();
        const wd = dvui.currentWindow().data();
        for (dvui.events()) |*e| {
            if (!dvui.eventMatchSimple(e, wd)) continue;
            if (suppress_close and ((e.evt == .window and e.evt.window.action == .close) or (e.evt == .app and e.evt.app.action == .quit))) {
                e.handle(@src(), wd);
            }
        }
    }

    const menu_action = if (zopts.force_dvui_menu)
        ztray_dvui.pollActionId()
    else
        ztray.pollActionId();

    if (menu_action) |raw| {
        if (std.enums.fromInt(menu_def.DemoAction, raw)) |action| {
            switch (action) {
                .say_hello => {
                    hello_count += 1;
                    const src: []const u8 = if (zopts.force_dvui_menu) "DVUI menu" else "native menu";
                    std.log.info("Hello from ztray ({s}) (#{d})", .{ src, hello_count });
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

    const hint =
        \\Default: native shell menu (Windows HMENU / macOS NSMenu / Linux D-Bus).
        \\In-app DVUI menu bar: zig build run-dvui -Dforce_dvui_menu=true
        \\
        \\From ztray/: zig build run-dvui
    ;
    dvui.labelNoFmt(@src(), hint, .{}, .{ .expand = .horizontal });

    dvui.Examples.demo(.lite);

    return .ok;
}
