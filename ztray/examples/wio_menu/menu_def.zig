//! Menu used by the ztray + wio native shell menu example.
const ztray = @import("ztray");

pub const DemoAction = enum(ztray.ActionId) {
    say_hello = 0,
    about = 1,
};

const file_items = [_]ztray.Item{
    .{ .action = .{
        .title = "Say Hello",
        .action_id = @intFromEnum(DemoAction.say_hello),
        .shortcut = .{ .key = .h, .primary = true },
    } },
};

const help_items = [_]ztray.Item{
    .{ .action = .{
        .title = "About",
        .action_id = @intFromEnum(DemoAction.about),
    } },
};

const menus = [_]ztray.Menu{
    .{ .title = "File", .items = &file_items },
    .{ .title = "Help", .items = &help_items },
};

pub const menu_bar: ztray.MenuBar = .{ .menus = &menus };
