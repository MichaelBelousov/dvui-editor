const std = @import("std");

const dvui = @import("dvui");
const Options = dvui.Options;

const dvui_editor = @import("../root.zig");
const App = dvui_editor.App;
const Editor = dvui_editor.Editor;

pub const TextEditWidget = @This();

id: dvui.Id = undefined,
file: *dvui_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *dvui_editor.Internal.TextFile) TextEditWidget {
    // TODO: Do we need src? How do we track multiple files?
    _ = src;
    return .{
        .file = file,
    };
}

pub fn deinit(_: TextEditWidget) void {
    // TODO: Free memory
}

pub fn processEvents(self: *TextEditWidget) void {
    const text_edit = dvui.textEntry(
        @src(),
        .{
            .placeholder = "My Awesome TextEdit Widget",
            .multiline = true,
            .cache_layout = true,
            .scroll_horizontal = true,
            .text = .{
                .buffer_dynamic = .{
                    .allocator = dvui_editor.app.gpa,
                    .backing = &self.file.content,
                },
            },
        },
        .{
            .expand = .both,
        },
    );
    defer text_edit.deinit();
}
