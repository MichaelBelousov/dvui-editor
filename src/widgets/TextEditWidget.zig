const std = @import("std");

const dvui = @import("dvui");

const inkz_editor = @import("../root.zig");
const App = inkz_editor.App;
const Editor = inkz_editor.Editor;
const Options = dvui.Options;

pub const TextEditWidget = @This();

id: dvui.Id = undefined,
file: *inkz_editor.Internal.TextFile = undefined,
first_run: bool = true,

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
    const box = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .background = false,
        .min_size_content = .{ .w = 40, .h = 100 },
    });
    defer box.deinit();

    const text_edit = dvui.textEntry(@src(), .{
        .placeholder = "My Awesome TextEdit Widget",
        .multiline = true,
    }, .{
        .expand = .both,
    });
    defer text_edit.deinit();

    if (self.first_run) {
        self.first_run = false;
        text_edit.textSet(self.file.content, false);
    }
}
