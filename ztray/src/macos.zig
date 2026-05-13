const std = @import("std");

const types = @import("types.zig");

extern fn ZTrayMacOSBeginMainMenu() bool;
extern fn ZTrayMacOSBeginMenu(title: [*:0]const u8) bool;
extern fn ZTrayMacOSAddItem(
    title: [*:0]const u8,
    action_id: c_int,
    key: [*:0]const u8,
    modifiers: u32,
    enabled: bool,
    suppress_next_window_close: bool,
) bool;
extern fn ZTrayMacOSAddSeparator() bool;
extern fn ZTrayMacOSEndMenu() bool;
extern fn ZTrayMacOSEndMainMenu() bool;
extern fn ZTrayMacOSPollAction() c_int;
extern fn ZTrayMacOSConsumeCloseTabSuppression() bool;

extern fn ZTrayMacOSTrayInstall(tooltip: [*:0]const u8, icon_path_utf8_or_null: ?[*:0]const u8, png_bytes: ?[*]const u8, png_len: usize) bool;
extern fn ZTrayMacOSTrayClearMenu() bool;
extern fn ZTrayMacOSTrayAddItem(
    title: [*:0]const u8,
    action_id: c_int,
    key: [*:0]const u8,
    modifiers: u32,
    enabled: bool,
    suppress_next_window_close: bool,
) bool;
extern fn ZTrayMacOSTrayAddSeparator() bool;
extern fn ZTrayMacOSTrayPollAction() c_int;
extern fn ZTrayMacOSTrayShutdown() void;
extern fn ZTrayMacOSPumpEventsTimeoutMs(ms: c_uint) void;

var macos_tray_active: std.atomic.Value(bool) = .init(false);

pub fn installMainMenu(allocator: std.mem.Allocator, menu_bar: types.MenuBar) error{ MenuInstallFailed, OutOfMemory }!void {
    if (!ZTrayMacOSBeginMainMenu()) return error.MenuInstallFailed;

    for (menu_bar.menus) |menu| {
        const title = try allocator.dupeZ(u8, menu.title);
        defer allocator.free(title);
        if (!ZTrayMacOSBeginMenu(title.ptr)) return error.MenuInstallFailed;

        for (menu.items) |item| {
            switch (item) {
                .separator => {
                    if (!ZTrayMacOSAddSeparator()) return error.MenuInstallFailed;
                },
                .action => |action| {
                    const item_title = try allocator.dupeZ(u8, action.title);
                    defer allocator.free(item_title);

                    const key = if (action.shortcut) |shortcut| try allocator.dupeZ(u8, shortcut.key) else try allocator.dupeZ(u8, "");
                    defer allocator.free(key);

                    const modifiers = if (action.shortcut) |shortcut| types.modifierMask(shortcut) else 0;
                    if (!ZTrayMacOSAddItem(
                        item_title.ptr,
                        action.action_id,
                        key.ptr,
                        modifiers,
                        action.enabled,
                        action.suppress_next_window_close,
                    )) return error.MenuInstallFailed;
                },
            }
        }

        if (!ZTrayMacOSEndMenu()) return error.MenuInstallFailed;
    }

    if (!ZTrayMacOSEndMainMenu()) return error.MenuInstallFailed;
}

pub fn pollActionId() c_int {
    return ZTrayMacOSPollAction();
}

pub fn consumeCloseTabSuppression() bool {
    return ZTrayMacOSConsumeCloseTabSuppression();
}

pub fn installTrayIcon(allocator: std.mem.Allocator, tooltip: []const u8, icon_file_utf8: ?[]const u8, icon_png: ?[]const u8) error{ TrayInstallFailed, TrayAlreadyInstalled, OutOfMemory }!void {
    if (macos_tray_active.swap(true, .acq_rel)) return error.TrayAlreadyInstalled;
    errdefer _ = macos_tray_active.store(false, .release);

    const tip_z = try allocator.dupeZ(u8, tooltip);
    defer allocator.free(tip_z);

    const icon_z: ?[:0]u8 = if (icon_file_utf8) |p| try allocator.dupeZ(u8, p) else null;
    defer if (icon_z) |z| allocator.free(z);

    const png = icon_png orelse "";
    const png_ptr: ?[*]const u8 = if (png.len > 0) png.ptr else null;

    if (!ZTrayMacOSTrayInstall(
        tip_z.ptr,
        if (icon_z) |z| z.ptr else null,
        png_ptr,
        png.len,
    )) {
        _ = macos_tray_active.store(false, .release);
        return error.TrayInstallFailed;
    }
}

pub fn setTrayMenu(allocator: std.mem.Allocator, menu: types.Menu) error{ OutOfMemory, MenuInstallFailed }!void {
    if (!macos_tray_active.load(.acquire)) return error.MenuInstallFailed;
    if (!ZTrayMacOSTrayClearMenu()) return error.MenuInstallFailed;

    for (menu.items) |item| {
        switch (item) {
            .separator => {
                if (!ZTrayMacOSTrayAddSeparator()) return error.MenuInstallFailed;
            },
            .action => |action| {
                const item_title = try allocator.dupeZ(u8, action.title);
                defer allocator.free(item_title);

                const key = if (action.shortcut) |shortcut| try allocator.dupeZ(u8, shortcut.key) else try allocator.dupeZ(u8, "");
                defer allocator.free(key);

                const modifiers = if (action.shortcut) |shortcut| types.modifierMask(shortcut) else 0;
                if (!ZTrayMacOSTrayAddItem(
                    item_title.ptr,
                    action.action_id,
                    key.ptr,
                    modifiers,
                    action.enabled,
                    action.suppress_next_window_close,
                )) return error.MenuInstallFailed;
            },
        }
    }
}

pub fn shutdownTray() void {
    if (!macos_tray_active.swap(false, .acq_rel)) return;
    ZTrayMacOSTrayShutdown();
}

pub fn pollTrayActionId() c_int {
    return ZTrayMacOSTrayPollAction();
}

pub fn pumpTrayEventsDarwin() void {
    ZTrayMacOSPumpEventsTimeoutMs(50);
}
