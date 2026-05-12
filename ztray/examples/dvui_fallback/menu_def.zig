//! Demo menu for the ztray + DVUI sample (native shell menu by default; in-app bar with `-Dforce_dvui_menu=true`).
const ztray = @import("ztray");

pub const DemoAction = enum(ztray.ActionId) {
    say_hello = 0,
    toggle_demo = 1,
    quit_hint = 2,
};

const file_items = [_]ztray.Item{
    .{ .action = .{
        .title = "Say Hello",
        .action_id = @intFromEnum(DemoAction.say_hello),
        .shortcut = .{ .key = "h", .modifiers = &.{.command} },
    } },
    .separator,
    .{ .action = .{
        .title = "Toggle DVUI Demo Window",
        .action_id = @intFromEnum(DemoAction.toggle_demo),
        .shortcut = .{ .key = "d", .modifiers = &.{.command} },
    } },
};

const help_items = [_]ztray.Item{
    .{ .action = .{
        .title = "About ztray fallback",
        .action_id = @intFromEnum(DemoAction.quit_hint),
    } },
};

const menus = [_]ztray.Menu{
    .{ .title = "File", .items = &file_items },
    .{ .title = "Help", .items = &help_items },
};

pub const menu_bar: ztray.MenuBar = .{ .menus = &menus };
