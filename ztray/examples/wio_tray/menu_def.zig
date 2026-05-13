//! Menubar and tray menus for the wio + native shell + tray example.
const ztray = @import("ztray");

pub const MenuBarAction = enum(ztray.ActionId) {
    say_hello = 0,
    about = 1,
};

const file_items = [_]ztray.Item{
    .{ .action = .{
        .title = "Say Hello",
        .action_id = @intFromEnum(MenuBarAction.say_hello),
        .shortcut = .{ .key = .h, .modifiers = &.{.primary} },
    } },
};

const help_items = [_]ztray.Item{
    .{ .action = .{
        .title = "About",
        .action_id = @intFromEnum(MenuBarAction.about),
    } },
};

const menus = [_]ztray.Menu{
    .{ .title = "File", .items = &file_items },
    .{ .title = "Help", .items = &help_items },
};

pub const menu_bar: ztray.MenuBar = .{ .menus = &menus };

pub const TrayAction = enum(c_int) {
    hello = 1,
    quit = 2,
};

const tray_items = [_]ztray.Item{
    .{ .action = .{
        .title = "Say hello (tray)",
        .action_id = @intFromEnum(TrayAction.hello),
    } },
    .separator,
    .{ .action = .{
        .title = "Quit",
        .action_id = @intFromEnum(TrayAction.quit),
    } },
};

pub const tray_menu: ztray.TrayMenu = .{
    .title = "Tray",
    .items = &tray_items,
};
