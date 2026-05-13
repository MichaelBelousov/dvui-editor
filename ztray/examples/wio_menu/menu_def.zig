//! Menu used by the ztray + wio native shell menu example.
const zmenu = @import("zmenu");

pub const DemoAction = enum(zmenu.ActionId) {
    say_hello = 0,
    about = 1,
};

const file_items = [_]zmenu.Item{
    .{ .action = .{
        .title = "Say Hello",
        .action_id = @intFromEnum(DemoAction.say_hello),
        .shortcut = .{ .key = .h, .primary = true },
    } },
};

const help_items = [_]zmenu.Item{
    .{ .action = .{
        .title = "About",
        .action_id = @intFromEnum(DemoAction.about),
    } },
};

const menus = [_]zmenu.Menu{
    .{ .title = "File", .items = &file_items },
    .{ .title = "Help", .items = &help_items },
};

pub const menu_bar: zmenu.MenuBar = .{ .menus = &menus };
