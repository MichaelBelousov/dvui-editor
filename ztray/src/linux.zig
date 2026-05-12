const std = @import("std");

const types = @import("types.zig");

pub const LinuxItemC = extern struct {
    id: i32,
    parent_id: i32,
    action_id: i32,
    flags: u32,
    label: [*:0]const u8,
};

extern fn ztray_linux_dbus_init() c_int;
extern fn ztray_linux_dbus_shutdown() void;
extern fn ztray_linux_dbus_set_items(items: [*]const LinuxItemC, n: c_int) c_int;
extern fn ztray_linux_dbus_dispatch() void;
extern fn ztray_linux_dbus_take_pending() c_int;

extern fn ztray_linux_tray_install(tooltip: [*:0]const u8, icon_name_or_null: ?[*:0]const u8) c_int;
extern fn ztray_linux_tray_shutdown() void;
extern fn ztray_linux_tray_set_items(items: [*]const LinuxItemC, n: c_int) c_int;
extern fn ztray_linux_tray_take_pending() c_int;

const FLAG_SEPARATOR: u32 = 1;
const FLAG_SUBMENU: u32 = 2;
const FLAG_DISABLED: u32 = 4;

var menu_installed: std.atomic.Value(bool) = .init(false);
var tray_session_active: std.atomic.Value(bool) = .init(false);

fn flattenSingleTrayMenu(allocator: std.mem.Allocator, menu: types.Menu) error{OutOfMemory}!std.ArrayList(LinuxItemC) {
    var flat: std.ArrayList(LinuxItemC) = .empty;
    errdefer {
        for (flat.items) |it| allocator.free(std.mem.span(it.label));
        flat.deinit(allocator);
    }

    var next_id: i32 = 1;
    try flat.append(allocator, .{
        .id = 0,
        .parent_id = -1,
        .action_id = -1,
        .flags = FLAG_SUBMENU,
        .label = (try allocator.dupeZ(u8, "")).ptr,
    });

    const menu_id = next_id;
    next_id += 1;
    try flat.append(allocator, .{
        .id = menu_id,
        .parent_id = 0,
        .action_id = -1,
        .flags = FLAG_SUBMENU,
        .label = (try allocator.dupeZ(u8, menu.title)).ptr,
    });

    for (menu.items) |item| {
        switch (item) {
            .separator => {
                const sid = next_id;
                next_id += 1;
                try flat.append(allocator, .{
                    .id = sid,
                    .parent_id = menu_id,
                    .action_id = -1,
                    .flags = FLAG_SEPARATOR,
                    .label = (try allocator.dupeZ(u8, "")).ptr,
                });
            },
            .action => |a| {
                const aid = next_id;
                next_id += 1;
                var fl: u32 = 0;
                if (!a.enabled) fl |= FLAG_DISABLED;
                try flat.append(allocator, .{
                    .id = aid,
                    .parent_id = menu_id,
                    .action_id = a.action_id,
                    .flags = fl,
                    .label = (try allocator.dupeZ(u8, a.title)).ptr,
                });
            },
        }
    }

    return flat;
}

pub fn installMainMenu(allocator: std.mem.Allocator, menu_bar: types.MenuBar) error{ DBusUnavailable, OutOfMemory }!void {
    if (menu_installed.load(.acquire)) return;

    var flat: std.ArrayList(LinuxItemC) = .empty;
    defer {
        for (flat.items) |it| allocator.free(std.mem.span(it.label));
        flat.deinit(allocator);
    }

    var next_id: i32 = 1;
    try flat.append(allocator, .{
        .id = 0,
        .parent_id = -1,
        .action_id = -1,
        .flags = FLAG_SUBMENU,
        .label = (try allocator.dupeZ(u8, "")).ptr,
    });

    for (menu_bar.menus) |menu| {
        const menu_id = next_id;
        next_id += 1;
        try flat.append(allocator, .{
            .id = menu_id,
            .parent_id = 0,
            .action_id = -1,
            .flags = FLAG_SUBMENU,
            .label = (try allocator.dupeZ(u8, menu.title)).ptr,
        });

        for (menu.items) |item| {
            switch (item) {
                .separator => {
                    const sid = next_id;
                    next_id += 1;
                    try flat.append(allocator, .{
                        .id = sid,
                        .parent_id = menu_id,
                        .action_id = -1,
                        .flags = FLAG_SEPARATOR,
                        .label = (try allocator.dupeZ(u8, "")).ptr,
                    });
                },
                .action => |a| {
                    const aid = next_id;
                    next_id += 1;
                    var fl: u32 = 0;
                    if (!a.enabled) fl |= FLAG_DISABLED;
                    try flat.append(allocator, .{
                        .id = aid,
                        .parent_id = menu_id,
                        .action_id = a.action_id,
                        .flags = fl,
                        .label = (try allocator.dupeZ(u8, a.title)).ptr,
                    });
                },
            }
        }
    }

    if (ztray_linux_dbus_init() == 0) return error.DBusUnavailable;
    errdefer ztray_linux_dbus_shutdown();

    if (ztray_linux_dbus_set_items(flat.items.ptr, @intCast(flat.items.len)) == 0) return error.DBusUnavailable;

    menu_installed.store(true, .release);
}

pub fn pollActionId() c_int {
    ztray_linux_dbus_dispatch();
    return ztray_linux_dbus_take_pending();
}

pub fn installTrayIcon(allocator: std.mem.Allocator, tooltip: []const u8, icon_name: ?[]const u8) error{ TrayInstallFailed, TrayAlreadyInstalled, OutOfMemory }!void {
    if (tray_session_active.swap(true, .acq_rel)) return error.TrayAlreadyInstalled;
    errdefer _ = tray_session_active.store(false, .release);

    const tip_z = try allocator.dupeZ(u8, tooltip);
    defer allocator.free(tip_z);
    const icon_z: ?[:0]u8 = if (icon_name) |n| try allocator.dupeZ(u8, n) else null;
    defer if (icon_z) |z| allocator.free(z);

    if (ztray_linux_tray_install(
        tip_z.ptr,
        if (icon_z) |z| z.ptr else null,
    ) == 0) {
        _ = tray_session_active.store(false, .release);
        return error.TrayInstallFailed;
    }
}

pub fn setTrayMenu(allocator: std.mem.Allocator, menu: types.Menu) error{ DBusUnavailable, OutOfMemory }!void {
    if (!tray_session_active.load(.acquire)) return error.DBusUnavailable;

    var flat = try flattenSingleTrayMenu(allocator, menu);
    defer {
        for (flat.items) |it| allocator.free(std.mem.span(it.label));
        flat.deinit(allocator);
    }

    if (ztray_linux_tray_set_items(flat.items.ptr, @intCast(flat.items.len)) == 0)
        return error.DBusUnavailable;
}

pub fn shutdownTray() void {
    if (!tray_session_active.swap(false, .acq_rel)) return;
    ztray_linux_tray_shutdown();
}

pub fn pollTrayActionId() c_int {
    ztray_linux_dbus_dispatch();
    return ztray_linux_tray_take_pending();
}

pub fn pumpLinuxDBus() void {
    ztray_linux_dbus_dispatch();
}

