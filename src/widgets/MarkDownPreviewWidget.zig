const std = @import("std");

const dvui = @import("dvui");

const dvui_editor = @import("../root.zig");

pub const MarkDownPreviewWidget = @This();

file: *dvui_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *dvui_editor.Internal.TextFile) MarkDownPreviewWidget {
    _ = src;
    return .{ .file = file };
}

pub fn deinit(_: MarkDownPreviewWidget) void {}

pub fn processEvents(self: *MarkDownPreviewWidget) void {
    dvui.labelNoFmt(
        @src(),
        "Markdown preview",
        .{},
        .{
            .expand = .both,
            .gravity_x = 0.5,
            .gravity_y = 0.5,
            .color_text = dvui.themeGet().color(.control, .text).opacity(0.6),
            .id_extra = self.file.id,
        },
    );
}
