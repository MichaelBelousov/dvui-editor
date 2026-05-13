const std = @import("std");

const dvui_editor = @import("../root.zig");
const MarkDownPreviewWidget = @import("MarkDownPreviewWidget.zig");

pub const MarkDownWidget = @This();

file: *dvui_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *dvui_editor.Internal.TextFile) MarkDownWidget {
    _ = src;
    return .{ .file = file };
}

pub fn deinit(_: MarkDownWidget) void {}

pub fn processEvents(self: *MarkDownWidget) void {
    const handle_size: f32 = 10;
    const handle_dist: f32 = 60;

    var paned = dvui_editor.dvui.paned(@src(), .{
        .direction = .horizontal,
        .collapsed_size = dvui_editor.editor.settings.min_window_size[0] + 1,
        .handle_size = handle_size,
        .handle_dynamic = .{ .handle_size_max = handle_size, .distance_max = handle_dist },
    }, .{
        .expand = .both,
        .background = false,
        .id_extra = self.file.id,
    });
    defer paned.deinit();

    if (paned.showFirst()) {
        var text_edit = dvui_editor.dvui.TextEditWidget.init(@src(), self.file);
        defer text_edit.deinit();
        text_edit.processEvents();
    }

    if (paned.showSecond()) {
        var preview = MarkDownPreviewWidget.init(@src(), self.file);
        defer preview.deinit();
        preview.processEvents();
    }
}
