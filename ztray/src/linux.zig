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

const FLAG_SEPARATOR: u32 = 1;
const FLAG_SUBMENU: u32 = 2;
const FLAG_DISABLED: u32 = 4;

var menu_installed: std.atomic.Value(bool) = .init(false);

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
