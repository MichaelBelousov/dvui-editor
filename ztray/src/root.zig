//! Host-agnostic native menu bar (macOS NSMenu, Win32 HMENU, Linux DBusMenu). No SDL or window toolkit dependency.
//! Optional compile-time DVUI immediate-mode menu via `ztray_build_options` + `drawMenuBar`.
const std = @import("std");
const builtin = @import("builtin");

const types = @import("types.zig");
const build_opts = @import("ztray_build_options");

pub const ActionId = types.ActionId;
pub const Modifier = types.Modifier;
pub const Shortcut = types.Shortcut;
pub const Item = types.Item;
pub const Menu = types.Menu;
pub const MenuBar = types.MenuBar;

pub const modifierMask = types.modifierMask;
pub const formatWindowsShortcut = types.formatWindowsShortcut;

const dvui_fb = if (build_opts.dvui_fallback)
    @import("dvui_fallback.zig")
else
    struct {
        pub fn installMainMenu(_: std.mem.Allocator, _: MenuBar) !void {}
        pub fn drawMenuBar() !void {}
        pub fn pollActionId() ?ActionId {
            return null;
        }
        pub fn shutdownMenu() void {}
    };

/// When compile-time DVUI fallback is enabled, draws the menu bar for this frame (immediate mode). No-op otherwise.
pub fn drawMenuBar() !void {
    if (!build_opts.dvui_fallback) return;
    try dvui_fb.drawMenuBar();
}

/// Release menu storage from [`installMainMenu`] when using DVUI fallback (optional).
pub fn shutdownDvuiMenu() void {
    if (!build_opts.dvui_fallback) return;
    dvui_fb.shutdownMenu();
}

/// Installs the menu bar. On Windows `hwnd` must be the top-level window handle; on macOS it is ignored.
/// When `force_dvui_menu` is set at compile time, registers an in-app DVUI menu only (call [`drawMenuBar`] each frame).
pub fn installMainMenu(allocator: std.mem.Allocator, menu_bar: MenuBar, hwnd: ?*anyopaque) !void {
    if (build_opts.dvui_fallback and build_opts.force_dvui_menu) {
        return dvui_fb.installMainMenu(allocator, menu_bar);
    }

    switch (builtin.os.tag) {
        .macos => return macos.installMainMenu(allocator, menu_bar),
        .windows => {
            const h = hwnd orelse return error.MissingWindowsHwnd;
            return windows.installMainMenu(allocator, h, menu_bar);
        },
        .linux => return linux.installMainMenu(allocator, menu_bar),
        else => {},
    }
}

/// Returns and clears the last menu action id, or null if none.
pub fn pollActionId() ?ActionId {
    if (build_opts.dvui_fallback and build_opts.force_dvui_menu) {
        return dvui_fb.pollActionId();
    }

    const id = switch (builtin.os.tag) {
        .macos => macos.pollActionId(),
        .windows => windows.pollActionId(),
        .linux => linux.pollActionId(),
        else => -1,
    };
    if (id < 0) return null;
    return id;
}

/// macOS only: whether the last "close tab" style action requested consuming the next window close / quit.
pub fn consumeCloseTabSuppression() bool {
    if (build_opts.force_dvui_menu) return false;
    return switch (builtin.os.tag) {
        .macos => macos.consumeCloseTabSuppression(),
        else => false,
    };
}

const macos = if (builtin.os.tag == .macos) @import("macos.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: MenuBar) !void {}
    fn pollActionId() c_int {
        return -1;
    }
    fn consumeCloseTabSuppression() bool {
        return false;
    }
};

const windows = if (builtin.os.tag == .windows) @import("windows.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: ?*anyopaque, _: MenuBar) error{OutOfMemory, MenuInstallFailed, ActionIdOutOfRange}!void {}
    fn pollActionId() c_int {
        return -1;
    }
};

const linux = if (builtin.os.tag == .linux) @import("linux.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: MenuBar) !void {}
    fn pollActionId() c_int {
        return -1;
    }
};
