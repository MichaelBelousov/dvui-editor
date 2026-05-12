//! Host-agnostic native menu bar (macOS NSMenu, Win32 HMENU, Linux DBusMenu). No SDL or window toolkit dependency.
//! Optional compile-time DVUI immediate-mode menu via `ztray_build_options` + `drawMenuBar`.
//!
//! **System tray** (`installTrayIcon`, `setTrayMenu`, `pollTrayActionId`, `shutdownTray`) is independent of the
//! menu bar API: use either, both, or neither. Tray uses native code even when `force_dvui_menu` is enabled.
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

/// Same [`Menu`] shape as menubar submenus; the root `title` is only used on some Linux paths.
pub const TrayMenu = Menu;

/// PNG bytes for the tray sample icon (`src/zig-favicon.png`, same image as `examples/zig-favicon.png`).
pub const zig_favicon_png = @embedFile("zig-favicon.png");

pub const modifierMask = types.modifierMask;
pub const formatWindowsShortcut = types.formatWindowsShortcut;

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

/// Pump native tray-related events (D-Bus on Linux, short Cocoa run-loop slice on macOS, `PeekMessage` on Windows).
pub fn pumpTrayEvents() void {
    switch (builtin.os.tag) {
        .linux => linux.pumpLinuxDBus(),
        .macos => macos.pumpTrayEventsDarwin(),
        .windows => windows.pumpTrayMessages(),
        else => {},
    }
}

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
    fn installMainMenu(_: std.mem.Allocator, _: MenuBar) !void {}
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
    fn installMainMenu(_: std.mem.Allocator, _: ?*anyopaque, _: MenuBar) error{OutOfMemory, MenuInstallFailed, ActionIdOutOfRange}!void {}
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

const linux = if (builtin.os.tag == .linux) @import("linux.zig") else struct {
    fn installMainMenu(_: std.mem.Allocator, _: MenuBar) !void {}
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