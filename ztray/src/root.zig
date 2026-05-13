//! Host-agnostic native menu bar (macOS NSMenu, Win32 HMENU, Linux DBusMenu). No SDL or window toolkit dependency.
//!
//! For an **in-app** menu bar with [DVUI](https://github.com/david-vanderson/dvui), depend on this package with DVUI and use **`createZtrayDvuiModule`** from `build.zig`: a single `addImport("ztray", ...)` exposes the same API as this file plus **`ztray.dvui_menu`** and **`installMainMenuForSdlDvuiWindow`** (see [`ztray_with_dvui.zig`](ztray_with_dvui.zig) and [`ztray_dvui.zig`](ztray_dvui.zig)). Pass the SDL module into **`createZtrayDvuiModule`** alongside DVUI. Optional **window chrome** (macOS vibrancy) is a separate module: **`createZchromeModule`** + `addImport("zchrome", ...)`. The core module rooted here does not import DVUI.
//! On Linux, [`appMenuRegistrarHasOwner`] reports whether a global AppMenu host is present (`false` → typical DVUI menubar fallback).
//!
//! **System tray** (`installTrayIcon`, `setTrayMenu`, `pollTrayActionId`, `shutdownTray`) is independent of the
//! menu bar API: use either, both, or neither.
//!
//! ## Threading and event loops
//!
//! Call **menu install**, **tray install**, and **setTrayMenu** from the same thread that runs the platform UI
//! (main thread): Win32 subclassing and `HWND`, AppKit, and Linux session D-Bus all expect that.
//!
//! - **Windows**: pump messages for the window that hosts the menubar (`PeekMessage` / your framework loop).
//!   For tray-only mode, call [`pumpTrayEvents`] so the internal message-only `HWND` receives tray callbacks.
//! - **macOS**: integrate with your `NSApplication` run loop; [`pumpTrayEvents`] runs a short event slice for
//!   the status item.
//! - **Linux**: [`pollActionId`], [`pollTrayActionId`], and [`pumpTrayEvents`] all dispatch the same D-Bus
//!   connection; calling more than one per frame is safe (redundant dispatches only).
//!
//! ## Strings and allocators
//!
//! Titles, tooltips, and shortcuts are **copied** into native or D-Bus storage during `installMainMenu` and
//! `setTrayMenu` (and related calls). You may free your `Menu` / `MenuBar` slices after a successful install.
const std = @import("std");
const builtin = @import("builtin");

const types = @import("types.zig");

pub const ActionId = types.ActionId;
pub const Modifier = types.Modifier;
pub const ShortcutKey = types.ShortcutKey;
pub const Shortcut = types.Shortcut;
pub const Item = types.Item;
pub const Menu = types.Menu;
pub const MenuBar = types.MenuBar;

/// Same [`Menu`] shape as menubar submenus; the root `title` is only used on some Linux paths.
pub const TrayMenu = Menu;

/// PNG bytes for the tray sample icon (`src/zig-favicon.png`, same image as `examples/zig-favicon.png`).
pub const zig_favicon_png = @embedFile("zig-favicon.png");

pub const modifierMask = types.modifierMask;
pub const formatWindowsShortcut = types.formatWindowsShortcut;
pub const formatShortcutMenuLabel = types.formatShortcutMenuLabel;

pub const TrayIconOptions = struct {
    tooltip: []const u8,
    /// Raw PNG bytes (e.g. `@embedFile("icon.png")`). When non-empty, used in preference to `icon_file` on macOS and Windows.
    icon_png: ?[]const u8 = null,
    /// Optional UTF-8 path to an icon file (e.g. `.ico` on Windows, image on macOS). On Linux prefer `linux_icon_name`.
    icon_file: ?[]const u8 = null,
    /// Freedesktop icon name for Linux StatusNotifierItem (`IconName`).
    linux_icon_name: ?[]const u8 = null,
    /// Windows only: HWND that receives tray callbacks; `null` uses an internal message-only window (tray-only apps).
    windows_hwnd: ?*anyopaque = null,
};

pub const InstallTrayIconError = error{ TrayInstallFailed, TrayAlreadyInstalled, OutOfMemory, InvalidWtf8 };
pub const SetTrayMenuError = error{ OutOfMemory, MenuInstallFailed, ActionIdOutOfRange, DBusUnavailable, InvalidWtf8 };

/// Every error [`installMainMenu`] can return on supported platforms (or missing `hwnd` on Windows).
pub const InstallMainMenuError = error{
    OutOfMemory,
    MenuInstallFailed,
    ActionIdOutOfRange,
    DBusUnavailable,
    MissingWindowsHwnd,
    UnsupportedPlatform,
    InvalidWtf8,
};

/// Pump native tray-related events (D-Bus on Linux, short Cocoa run-loop slice on macOS, `PeekMessage` on Windows).
pub fn pumpTrayEvents() void {
    switch (builtin.os.tag) {
        .linux => linux.pumpLinuxDBus(),
        .macos => macos.pumpTrayEventsDarwin(),
        .windows => windows.pumpTrayMessages(),
        else => {},
    }
}

/// Installs the **native** menu bar. On Windows `hwnd` must be the top-level window handle; on macOS it is ignored.
pub fn installMainMenu(allocator: std.mem.Allocator, menu_bar: MenuBar, hwnd: ?*anyopaque) InstallMainMenuError!void {
    switch (builtin.os.tag) {
        .macos => return macos.installMainMenu(allocator, menu_bar),
        .windows => {
            const h = hwnd orelse return error.MissingWindowsHwnd;
            return windows.installMainMenu(allocator, h, menu_bar);
        },
        .linux => return linux.installMainMenu(allocator, menu_bar),
        else => return error.UnsupportedPlatform,
    }
}

/// Linux: whether `com.canonical.AppMenu.Registrar` has a session-bus owner (global menubar). `false` means no host—DVUI in-app menubar is a typical fallback. Non-Linux or unknown (D-Bus error, stub build): `null`.
pub fn appMenuRegistrarHasOwner() ?bool {
    return switch (builtin.os.tag) {
        .linux => linux.appMenuRegistrarHasOwner(),
        else => null,
    };
}

/// Returns and clears the last **native** menubar action id, or null if none.
pub fn pollActionId() ?ActionId {
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
    return switch (builtin.os.tag) {
        .macos => macos.consumeCloseTabSuppression(),
        else => false,
    };
}

pub fn installTrayIcon(allocator: std.mem.Allocator, options: TrayIconOptions) InstallTrayIconError!void {
    switch (builtin.os.tag) {
        .macos => return macos.installTrayIcon(allocator, options.tooltip, options.icon_file, options.icon_png),
        .windows => return windows.installTrayIcon(
            allocator,
            @ptrCast(options.windows_hwnd orelse null),
            options.tooltip,
            options.icon_file,
            options.icon_png,
        ),
        .linux => return linux.installTrayIcon(allocator, options.tooltip, options.linux_icon_name orelse options.icon_file, options.icon_png),
        else => return error.TrayInstallFailed,
    }
}

pub fn setTrayMenu(allocator: std.mem.Allocator, menu: TrayMenu) SetTrayMenuError!void {
    switch (builtin.os.tag) {
        .macos => return macos.setTrayMenu(allocator, menu),
        .windows => return windows.setTrayMenu(allocator, menu),
        .linux => return linux.setTrayMenu(allocator, menu),
        else => return error.MenuInstallFailed,
    }
}

pub fn pollTrayActionId() ?ActionId {
    const id = switch (builtin.os.tag) {
        .macos => macos.pollTrayActionId(),
        .windows => windows.pollTrayActionId(),
        .linux => linux.pollTrayActionId(),
        else => -1,
    };
    if (id < 0) return null;
    return id;
}

pub fn shutdownTray() void {
    switch (builtin.os.tag) {
        .macos => macos.shutdownTray(),
        .windows => windows.shutdownTray(),
        .linux => linux.shutdownTray(),
        else => {},
    }
}

const macos = if (builtin.os.tag == .macos) @import("macos.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: MenuBar) InstallMainMenuError!void {}
    fn pollActionId() c_int {
        return -1;
    }
    fn consumeCloseTabSuppression() bool {
        return false;
    }
    fn installTrayIcon(_: std.mem.Allocator, _: []const u8, _: ?[]const u8, _: ?[]const u8) InstallTrayIconError!void {
        return error.TrayInstallFailed;
    }
    fn setTrayMenu(_: std.mem.Allocator, _: Menu) SetTrayMenuError!void {
        return error.MenuInstallFailed;
    }
    fn shutdownTray() void {}
    fn pollTrayActionId() c_int {
        return -1;
    }
    fn pumpTrayEventsDarwin() void {}
};

const windows = if (builtin.os.tag == .windows) @import("windows.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: ?*anyopaque, _: MenuBar) InstallMainMenuError!void {}
    fn pollActionId() c_int {
        return -1;
    }
    fn installTrayIcon(_: std.mem.Allocator, _: ?*anyopaque, _: []const u8, _: ?[]const u8, _: ?[]const u8) InstallTrayIconError!void {
        return error.TrayInstallFailed;
    }
    fn setTrayMenu(_: std.mem.Allocator, _: Menu) SetTrayMenuError!void {
        return error.MenuInstallFailed;
    }
    fn shutdownTray() void {}
    fn pollTrayActionId() c_int {
        return -1;
    }
    fn pumpTrayMessages() void {}
};

/// Inclusive maximum `Item.action.action_id` for the Windows **menubar** (`WM_COMMAND` packing).
pub const windows_menubar_action_id_max: u16 = if (builtin.os.tag == .windows)
    windows.menubar_action_id_max
else
    0xFFFF - 0x7000;

/// Inclusive maximum `action_id` for the Windows **tray** popup on the same `HWND` as the menubar.
pub const windows_tray_action_id_max: u16 = if (builtin.os.tag == .windows)
    windows.tray_action_id_max
else
    0xFFFF - 0x7580;

comptime {
    if (builtin.os.tag == .windows) {
        std.debug.assert(windows_menubar_action_id_max == windows.menubar_action_id_max);
        std.debug.assert(windows_tray_action_id_max == windows.tray_action_id_max);
    }
}

const linux = if (builtin.os.tag == .linux) @import("linux.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: MenuBar) InstallMainMenuError!void {}
    fn pollActionId() c_int {
        return -1;
    }
    fn installTrayIcon(_: std.mem.Allocator, _: []const u8, _: ?[]const u8, _: ?[]const u8) InstallTrayIconError!void {
        return error.TrayInstallFailed;
    }
    fn setTrayMenu(_: std.mem.Allocator, _: Menu) SetTrayMenuError!void {
        return error.MenuInstallFailed;
    }
    fn shutdownTray() void {}
    fn pollTrayActionId() c_int {
        return -1;
    }
    fn pumpLinuxDBus() void {}
};
