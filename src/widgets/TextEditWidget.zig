const std = @import("std");

const dvui = @import("dvui");

const inkz_editor = @import("../root.zig");
const App = inkz_editor.App;
const Editor = inkz_editor.Editor;

pub const TextEditWidget = @This();

pub fn init() !TextEditWidget {
    return .{};
}

pub fn deinit() void {
    // TODO: Free memory
}

pub fn draw(_: TextEditWidget) !bool {
    const box = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .background = false,
        .min_size_content = .{ .w = 40, .h = 100 },
    });
    defer box.deinit();

    const text_edit = dvui.textEntry(@src(), .{ .placeholder = "My Awesome TextEdit Widget" }, .{
        .expand = .both,
    });

    defer text_edit.deinit();

    return true;
}
