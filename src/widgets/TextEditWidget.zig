const std = @import("std");

const dvui = @import("dvui");

const inkz_editor = @import("../root.zig");
const App = inkz_editor.App;
const Editor = inkz_editor.Editor;
const Options = dvui.Options;

pub const TextEditWidget = @This();

id: dvui.Id = undefined,
file: *inkz_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *inkz_editor.Internal.TextFile) TextEditWidget {
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
                    .allocator = inkz_editor.app.gpa,
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
