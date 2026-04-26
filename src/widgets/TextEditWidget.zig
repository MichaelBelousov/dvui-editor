const std = @import("std");

const dvui = @import("dvui");

const inkz_editor = @import("../root.zig");
const App = inkz_editor.App;
const Editor = inkz_editor.Editor;
const Options = dvui.Options;

pub const TextEditWidget = @This();

id: dvui.Id = undefined,
wd: dvui.WidgetData = undefined,
file: *inkz_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *inkz_editor.Internal.TextFile, opts: Options) TextEditWidget {
    const defaults: Options = .{
        .name = "TextEditWidget",
    };
    const wd = dvui.WidgetData.init(src, .{}, defaults.override(opts));

    return .{
        .wd = wd,
        .file = file,
    };
}

pub fn deinit(_: TextEditWidget) void {
    // TODO: Free memory
}

pub fn draw(_: TextEditWidget) bool {
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

pub fn processEvents(self: TextEditWidget) void {
    _ = self.draw();
}
