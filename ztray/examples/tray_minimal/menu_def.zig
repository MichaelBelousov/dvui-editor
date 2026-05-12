//! Tray menu for the minimal tray-only example (no menubar).
const ztray = @import("ztray");

pub const TrayAction = enum(c_int) {
    hello = 1,
    quit = 2,
};

const items = [_]ztray.Item{
    .{ .action = .{
        .title = "Say hello",
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
    .items = &items,
};
