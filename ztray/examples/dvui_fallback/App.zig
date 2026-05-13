//! DVUI app + ztray: **native** shell menu by default; in-app DVUI menu bar with `-Dforce_dvui_menu=true`
//! or on Linux when `com.canonical.AppMenu.Registrar` has no D-Bus owner.
const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
const sdl3 = @import("sdl-backend").c;
const zopts = @import("zmenu_dvui_opts");
const zmenu = @import("zmenu");

const menu_def = @import("menu_def.zig");

var hello_count: u32 = 0;
var use_dvui_menu: bool = false;

fn menuHostHwnd(win: *dvui.Window) ?*anyopaque {
    if (comptime builtin.os.tag != .windows) return null;
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
    .title = "ztray + DVUI",
    .transparent = if (builtin.os.tag == .macos or builtin.os.tag == .windows) true else false,
} }, .frameFn = AppFrame, .initFn = AppInit, .deinitFn = AppDeinit };

pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

pub fn AppInit(win: *dvui.Window) !void {
    use_dvui_menu = zopts.force_dvui_menu or (builtin.os.tag == .linux and zmenu.appMenuRegistrarHasOwner() == false);

    if (use_dvui_menu) {
        dvui_menu_install_and_sync: {
            zmenu.dvui_menu.installMainMenu(win.gpa, menu_def.menu_bar) catch |err| {
                std.log.err("zmenu.dvui_menu installMainMenu: {s}", .{@errorName(err)});
                break :dvui_menu_install_and_sync;
            };
            zmenu.dvui_menu.syncMenuShortcuts(win) catch |err| {
                std.log.err("zmenu.dvui_menu syncMenuShortcuts: {s}", .{@errorName(err)});
            };
        }
    } else {
        zmenu.installMainMenu(win.gpa, menu_def.menu_bar, .{ .windows_hwnd = menuHostHwnd(win) }) catch |err| {
            std.log.err("ztray installMainMenu: {s}", .{@errorName(err)});
        };
    }
}

pub fn AppDeinit() void {
    if (use_dvui_menu) {
        zmenu.dvui_menu.shutdownMenu();
    }
}

pub fn AppFrame() !dvui.App.Result {
    if (use_dvui_menu) {
        try zmenu.dvui_menu.drawMenuBar();
    }

    const menu_action = if (use_dvui_menu)
        zmenu.dvui_menu.pollAction(menu_def.DemoAction)
    else
        zmenu.pollAction(menu_def.DemoAction);

    if (menu_action) |action| {
        switch (action) {
            .say_hello => {
                hello_count += 1;
                const src: []const u8 = if (use_dvui_menu) "DVUI menu" else "native menu";
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

    var box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
    defer box.deinit();

    const hint =
        \\Default: native shell menu (Windows HMENU / macOS NSMenu / Linux D-Bus when an AppMenu registrar exists).
        \\On Linux, if com.canonical.AppMenu.Registrar has no owner, the sample uses an in-app DVUI menu bar automatically.
        \\Force in-app DVUI menu on all platforms: zig build run-dvui -Dforce_dvui_menu=true
        \\
        \\From ztray/: zig build run-dvui
    ;
    dvui.labelNoFmt(@src(), hint, .{}, .{ .expand = .horizontal });

    dvui.Examples.demo(.lite);

    return .ok;
}
