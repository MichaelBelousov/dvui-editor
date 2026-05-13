const std = @import("std");

const dvui_editor = @import("../root.zig");
const CodeEditorWidget = @import("CodeEditorWidget.zig");
const InkPreviewWidget = @import("InkPreviewWidget.zig");

pub const InkEditorWidget = @This();

file: *dvui_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *dvui_editor.Internal.TextFile) InkEditorWidget {
    _ = src;
    return .{ .file = file };
}

pub fn deinit(_: InkEditorWidget) void {}

pub fn processEvents(self: *InkEditorWidget) void {
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
        var code_edit = CodeEditorWidget.init(@src(), self.file);
        defer code_edit.deinit();
        code_edit.processEvents();
    }

    if (paned.showSecond()) {
        var preview = InkPreviewWidget.init(@src(), self.file);
        defer preview.deinit();
        preview.processEvents();
    }
}
