const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");

pub const Action = enum(c_int) {
    open_folder = 0,
    open_files = 1,
    save = 2,
    copy = 3,
    paste = 4,
    close_tab = 5,
    undo = 6,
    redo = 7,
    toggle_explorer = 8,
    show_dvui_demo = 9,
};

pub const Modifier = enum(u8) {
    command,
    shift,
    option,
    control,
};

pub const Shortcut = struct {
    key: []const u8,
    modifiers: []const Modifier = &.{},
};

pub const Item = union(enum) {
    action: ActionItem,
    separator,

    pub const ActionItem = struct {
        title: []const u8,
        action: Action,
        shortcut: ?Shortcut = null,
        enabled: bool = true,
    };
};

pub const Menu = struct {
    title: []const u8,
    items: []const Item,
};

pub const MenuBar = struct {
    menus: []const Menu,
};

const file_menu_items = [_]Item{
    .{ .action = .{ .title = "Open Folder", .action = .open_folder, .shortcut = .{ .key = "f", .modifiers = &.{.command} } } },
    .{ .action = .{ .title = "Open Files", .action = .open_files, .shortcut = .{ .key = "o", .modifiers = &.{.command} } } },
    .separator,
    .{ .action = .{ .title = "Save", .action = .save, .shortcut = .{ .key = "s", .modifiers = &.{.command} } } },
    .{ .action = .{ .title = "Close Tab", .action = .close_tab, .shortcut = .{ .key = "w", .modifiers = &.{.command} } } },
};

const edit_menu_items = [_]Item{
    .{ .action = .{ .title = "Copy", .action = .copy, .shortcut = .{ .key = "c", .modifiers = &.{.command} } } },
    .{ .action = .{ .title = "Paste", .action = .paste, .shortcut = .{ .key = "v", .modifiers = &.{.command} } } },
    .separator,
    .{ .action = .{ .title = "Undo", .action = .undo, .shortcut = .{ .key = "z", .modifiers = &.{.command} }, .enabled = false } },
    .{ .action = .{ .title = "Redo", .action = .redo, .shortcut = .{ .key = "z", .modifiers = &.{ .command, .shift } }, .enabled = false } },
};

const view_menu_items = [_]Item{
    .{ .action = .{ .title = "Show Explorer", .action = .toggle_explorer, .shortcut = .{ .key = "e", .modifiers = &.{.command} } } },
    .separator,
    .{ .action = .{ .title = "Show DVUI Demo", .action = .show_dvui_demo } },
};

const default_menus = [_]Menu{
    .{ .title = "File", .items = &file_menu_items },
    .{ .title = "Edit", .items = &edit_menu_items },
    .{ .title = "View", .items = &view_menu_items },
};

pub const default_menu_bar = MenuBar{ .menus = &default_menus };

pub fn installDefaultMainMenu(allocator: std.mem.Allocator, window: *dvui.Window) !void {
    try installMainMenu(allocator, window, default_menu_bar);
}

pub fn installMainMenu(allocator: std.mem.Allocator, window: *dvui.Window, menu_bar: MenuBar) !void {
    switch (builtin.os.tag) {
        .macos => try macos.installMainMenu(allocator, menu_bar),
        .windows => try windows.installMainMenu(allocator, window, menu_bar),
        else => {},
    }
}

pub fn pollAction() ?Action {
    const id = switch (builtin.os.tag) {
        .macos => macos.pollActionId(),
        .windows => windows.pollActionId(),
        else => -1,
    };
    if (id < 0 or id > @intFromEnum(Action.show_dvui_demo)) return null;
    return @enumFromInt(id);
}

pub fn consumeCloseTabSuppression() bool {
    return switch (builtin.os.tag) {
        .macos => macos.consumeCloseTabSuppression(),
        else => false,
    };
}

pub fn modifierMask(shortcut: Shortcut) u32 {
    var mask: u32 = 0;
    for (shortcut.modifiers) |modifier| {
        mask |= switch (modifier) {
            .command => 1 << 0,
            .shift => 1 << 1,
            .option => 1 << 2,
            .control => 1 << 3,
        };
    }
    return mask;
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
    fn installMainMenu(_: std.mem.Allocator, _: *dvui.Window, _: MenuBar) !void {}
    fn pollActionId() c_int {
        return -1;
    }
};
