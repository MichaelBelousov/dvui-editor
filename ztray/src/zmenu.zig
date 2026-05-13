//! Native menu bar: macOS NSMenu, Win32 HMENU, Linux D-Bus AppMenu.
//!
//! For an **in-app** DVUI menu bar, use `createZmenuDvuiModule` from `build.zig` — one `addImport("zmenu", …)` gives the same API plus `zmenu.dvui_menu`.
//! On Linux, [`appMenuRegistrarHasOwner`] reports whether a global AppMenu host is present.
//!
//! ## Threading and event loops
//!
//! Call `installMainMenu` from the main thread. On Windows pump messages via your framework loop.
//! On Linux and macOS call [`pumpEvents`] each frame; it is safe to call from either zmenu or ztray.
//!
//! ## Strings and allocators
//!
//! Titles and shortcuts are copied during `installMainMenu`. Free your slices after the call.
const std = @import("std");
const builtin = @import("builtin");

const types = @import("types.zig");

pub const ActionId = types.ActionId;
pub const ShortcutKey = types.ShortcutKey;
pub const Shortcut = types.Shortcut;
pub const Item = types.Item;
pub const Menu = types.Menu;
pub const MenuBar = types.MenuBar;

pub const modifierMask = types.modifierMask;
pub const formatWindowsShortcut = types.formatWindowsShortcut;
pub const formatShortcutMenuLabel = types.formatShortcutMenuLabel;

pub const MenuBarOptions = struct {
    /// Windows only: top-level HWND for the menu bar. Required on Windows; ignored elsewhere.
    windows_hwnd: ?*anyopaque = null,
};

pub const InstallMainMenuError = error{
    OutOfMemory,
    MenuInstallFailed,
    ActionIdOutOfRange,
    DBusUnavailable,
    MissingWindowsHwnd,
    UnsupportedPlatform,
    InvalidWtf8,
};

/// Pump native events: D-Bus on Linux (shared connection with ztray), short Cocoa run-loop slice on macOS, `PeekMessage` on Windows.
pub fn pumpEvents() void {
    switch (builtin.os.tag) {
        .linux => linux.pumpLinuxDBus(),
        .macos => macos.pumpTrayEventsDarwin(),
        .windows => win.pumpTrayMessages(),
        else => {},
    }
}

/// Installs the native menu bar. On Windows set `options.windows_hwnd` to the top-level window handle.
pub fn installMainMenu(allocator: std.mem.Allocator, menu_bar: MenuBar, options: MenuBarOptions) InstallMainMenuError!void {
    switch (builtin.os.tag) {
        .macos => return macos.installMainMenu(allocator, menu_bar),
        .windows => {
            const h = options.windows_hwnd orelse return error.MissingWindowsHwnd;
            return win.installMainMenu(allocator, h, menu_bar);
        },
        .linux => return linux.installMainMenu(allocator, menu_bar),
        else => return error.UnsupportedPlatform,
    }
}

/// Linux: whether `com.canonical.AppMenu.Registrar` has a session-bus owner. `null` on non-Linux or D-Bus error.
pub fn appMenuRegistrarHasOwner() ?bool {
    return switch (builtin.os.tag) {
        .linux => linux.appMenuRegistrarHasOwner(),
        else => null,
    };
}

/// Returns and clears the last native menubar action id, or null if none.
pub fn pollActionId() ?ActionId {
    const id = switch (builtin.os.tag) {
        .macos => macos.pollActionId(),
        .windows => win.pollActionId(),
        .linux => linux.pollActionId(),
        else => -1,
    };
    if (id < 0) return null;
    return id;
}

/// Typed poll: returns the action id cast to `T`, or null if none pending.
pub fn pollAction(comptime T: type) ?T {
    const id = pollActionId() orelse return null;
    return std.enums.fromInt(T, id);
}

/// Windows-internal action ID limit for the menu bar (`WM_COMMAND` packing).
pub const windows = struct {
    pub const menubar_action_id_max: u16 = if (builtin.os.tag == .windows)
        @import("windows.zig").menubar_action_id_max
    else
        0xFFFF - 0x7000;
};

const macos = if (builtin.os.tag == .macos) @import("macos.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: MenuBar) InstallMainMenuError!void {}
    fn pollActionId() c_int { return -1; }
    fn pumpTrayEventsDarwin() void {}
};

const win = if (builtin.os.tag == .windows) @import("windows.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: ?*anyopaque, _: MenuBar) InstallMainMenuError!void {}
    fn pollActionId() c_int { return -1; }
    fn pumpTrayMessages() void {}
};

const linux = if (builtin.os.tag == .linux) @import("linux.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: MenuBar) InstallMainMenuError!void {}
    fn pollActionId() c_int { return -1; }
    fn pumpLinuxDBus() void {}
    fn appMenuRegistrarHasOwner() ?bool { return null; }
};
