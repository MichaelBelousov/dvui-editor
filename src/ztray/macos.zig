const std = @import("std");

const ztray = @import("main.zig");

extern fn ZTrayMacOSBeginMainMenu() bool;
extern fn ZTrayMacOSBeginMenu(title: [*:0]const u8) bool;
extern fn ZTrayMacOSAddItem(title: [*:0]const u8, action_id: c_int, key: [*:0]const u8, modifiers: u32, enabled: bool) bool;
extern fn ZTrayMacOSAddSeparator() bool;
extern fn ZTrayMacOSEndMenu() bool;
extern fn ZTrayMacOSEndMainMenu() bool;
extern fn ZTrayMacOSPollAction() c_int;
extern fn ZTrayMacOSConsumeCloseTabSuppression() bool;

pub fn installMainMenu(allocator: std.mem.Allocator, menu_bar: ztray.MenuBar) !void {
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

                    const modifiers = if (action.shortcut) |shortcut| ztray.modifierMask(shortcut) else 0;
                    if (!ZTrayMacOSAddItem(item_title.ptr, @intFromEnum(action.action), key.ptr, modifiers, action.enabled)) {
                        return error.MenuInstallFailed;
                    }
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
