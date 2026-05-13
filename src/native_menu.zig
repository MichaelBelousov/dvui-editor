const zmenu = @import("zmenu");

/// Action ids delivered by the native menu bar (must match values passed in `main_menu_bar`).
pub const NativeMenuAction = enum(c_int) {
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

const file_menu_items = [_]zmenu.Item{
    .{ .action = .{
        .title = "Open Folder",
        .action_id = @intFromEnum(NativeMenuAction.open_folder),
        .shortcut = .{ .key = .f, .primary = true },
    } },
    .{ .action = .{
        .title = "Open Files",
        .action_id = @intFromEnum(NativeMenuAction.open_files),
        .shortcut = .{ .key = .o, .primary = true },
    } },
    .separator,
    .{ .action = .{
        .title = "Save",
        .action_id = @intFromEnum(NativeMenuAction.save),
        .shortcut = .{ .key = .s, .primary = true },
    } },
    .{ .action = .{
        .title = "Close Tab",
        .action_id = @intFromEnum(NativeMenuAction.close_tab),
        .shortcut = .{ .key = .w, .primary = true },
    } },
};

const edit_menu_items = [_]zmenu.Item{
    .{ .action = .{
        .title = "Copy",
        .action_id = @intFromEnum(NativeMenuAction.copy),
        .shortcut = .{ .key = .c, .primary = true },
    } },
    .{ .action = .{
        .title = "Paste",
        .action_id = @intFromEnum(NativeMenuAction.paste),
        .shortcut = .{ .key = .v, .primary = true },
    } },
    .separator,
    .{ .action = .{
        .title = "Undo",
        .action_id = @intFromEnum(NativeMenuAction.undo),
        .shortcut = .{ .key = .z, .primary = true },
        .enabled = false,
    } },
    .{ .action = .{
        .title = "Redo",
        .action_id = @intFromEnum(NativeMenuAction.redo),
        .shortcut = .{ .key = .z, .primary = true, .shift = true },
        .enabled = false,
    } },
};

const view_menu_items = [_]zmenu.Item{
    .{ .action = .{
        .title = "Show Explorer",
        .action_id = @intFromEnum(NativeMenuAction.toggle_explorer),
        .shortcut = .{ .key = .e, .primary = true },
    } },
    .separator,
    .{ .action = .{
        .title = "Show DVUI Demo",
        .action_id = @intFromEnum(NativeMenuAction.show_dvui_demo),
    } },
};

const main_menus = [_]zmenu.Menu{
    .{ .title = "File", .items = &file_menu_items },
    .{ .title = "Edit", .items = &edit_menu_items },
    .{ .title = "View", .items = &view_menu_items },
};

pub const main_menu_bar: zmenu.MenuBar = .{ .menus = &main_menus };
