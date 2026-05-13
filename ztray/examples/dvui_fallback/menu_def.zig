//! Demo menu for the ztray + DVUI sample (native shell menu by default; in-app bar with `-Dforce_dvui_menu=true` on the sample build).
const zmenu = @import("zmenu");

pub const DemoAction = enum(zmenu.ActionId) {
    say_hello = 0,
    toggle_demo = 1,
    quit_hint = 2,
};

const file_items = [_]zmenu.Item{
    .{ .action = .{
        .title = "Say Hello",
        .action_id = @intFromEnum(DemoAction.say_hello),
        .shortcut = .{ .key = .a, .primary = true },
    } },
    .separator,
    .{ .action = .{
        .title = "Toggle DVUI Demo Window",
        .action_id = @intFromEnum(DemoAction.toggle_demo),
        .shortcut = .{ .key = .d, .primary = true },
    } },
};

const help_items = [_]zmenu.Item{
    .{ .action = .{
        .title = "About ztray fallback",
        .action_id = @intFromEnum(DemoAction.quit_hint),
    } },
};

const menus = [_]zmenu.Menu{
    .{ .title = "File", .items = &file_items },
    .{ .title = "Help", .items = &help_items },
};

pub const menu_bar: zmenu.MenuBar = .{ .menus = &menus };
