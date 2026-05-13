//! Combined zmenu + DVUI in-app menubar. Owns the native-vs-DVUI decision so callers don't branch.
//!
//! Use `installMainMenu` with `force_dvui = true` (or let Linux auto-detect) then call `drawMenuBar`,
//! `pollAction`, and `shutdownMenu` without any platform branching.
const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const zc = @import("zmenu_core");

pub const ActionId = zc.ActionId;
pub const ShortcutKey = zc.ShortcutKey;
pub const Shortcut = zc.Shortcut;
pub const Item = zc.Item;
pub const Menu = zc.Menu;
pub const MenuBar = zc.MenuBar;

pub const modifierMask = zc.modifierMask;
pub const formatWindowsShortcut = zc.formatWindowsShortcut;
pub const formatShortcutMenuLabel = zc.formatShortcutMenuLabel;

pub const InstallMainMenuError = zc.InstallMainMenuError;
pub const pumpEvents = zc.pumpEvents;
pub const appMenuRegistrarHasOwner = zc.appMenuRegistrarHasOwner;
pub const pollActionId = zc.pollActionId;
pub const windows = zc.windows;

pub const MenuBarOptions = struct {
    /// Windows only: top-level HWND. Required on Windows for native menu; ignored elsewhere.
    windows_hwnd: ?*anyopaque = null,
    /// Use the in-app DVUI menu bar instead of the native shell menu.
    /// On Linux, also falls back to DVUI automatically when no AppMenu registrar is present.
    force_dvui: bool = false,
};

var g_use_dvui: bool = false;

const dvui_menu_impl = @import("zmenu_dvui.zig");

/// Installs the menu bar. Decides native vs. DVUI internally based on `options.force_dvui` and
/// Linux AppMenu availability. Call `drawMenuBar` / `pollAction` / `shutdownMenu` without branching.
pub fn installMainMenu(allocator: std.mem.Allocator, menu_bar: MenuBar, options: MenuBarOptions) InstallMainMenuError!void {
    g_use_dvui = options.force_dvui or
        (builtin.os.tag == .linux and zc.appMenuRegistrarHasOwner() == false);

    if (g_use_dvui) {
        try dvui_menu_impl.installMainMenu(allocator, menu_bar);
        dvui_menu_impl.syncMenuShortcuts(dvui.currentWindow()) catch {};
    } else {
        try zc.installMainMenu(allocator, menu_bar, .{ .windows_hwnd = options.windows_hwnd });
    }
}

/// Draw the in-app DVUI menu bar. No-op when using the native shell menu.
pub fn drawMenuBar() !void {
    if (g_use_dvui) try dvui_menu_impl.drawMenuBar();
}

/// Typed poll from whichever menu source is active.
pub fn pollAction(comptime T: type) ?T {
    if (g_use_dvui) return dvui_menu_impl.pollAction(T);
    return zc.pollAction(T);
}

/// Shut down the in-app DVUI menu. No-op when using the native shell menu.
pub fn shutdownMenu() void {
    if (g_use_dvui) dvui_menu_impl.shutdownMenu();
}

pub const installMainMenuForSdlDvuiWindow = dvui_menu_impl.installMainMenuForSdlDvuiWindow;

/// Internal: access the underlying DVUI menu module directly when needed.
pub const dvui_menu = dvui_menu_impl;
