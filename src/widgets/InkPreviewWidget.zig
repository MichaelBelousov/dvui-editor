const std = @import("std");
const dvui = @import("dvui");

const dvui_editor = @import("../root.zig");

pub const InkPreviewWidget = @This();

file: *dvui_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *dvui_editor.Internal.TextFile) InkPreviewWidget {
    _ = src;
    return .{ .file = file };
}

pub fn deinit(_: InkPreviewWidget) void {}

pub fn processEvents(self: *InkPreviewWidget) void {
    dvui.labelNoFmt(
        @src(),
        "Ink preview",
        .{},
        .{
            .expand = .both,
            .gravity_x = 0.5,
            .gravity_y = 0.5,
            .id_extra = self.file.id,
        },
    );
}
