//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const App = @import("App.zig");
pub const Editor = @import("Editor.zig");

pub var app: *App = undefined;
pub var editor: *Editor = undefined;

pub const Internal = struct {
    // pub const Animation = @import("internal/Animation.zig");
    // pub const Atlas = @import("internal/Atlas.zig");
    // pub const Buffers = @import("internal/Buffers.zig");
    // pub const File = @import("internal/File.zig");
    // pub const History = @import("internal/History.zig");
    pub const Palette = @import("internal/Palette.zig");
    pub const TextFile = @import("internal/TextFile.zig");
    pub const NativeMenuAction = enum(c_int) {
        open_folder = 0,
        open_files = 1,
        save = 2,
        copy = 3,
        paste = 4,
        undo = 5,
        redo = 6,
        transform = 7,
        toggle_explorer = 8,
        show_dvui_demo = 9,
    };
};

pub const math = struct {
    pub const Color = @import("color.zig").Color;
};

pub const dvui = @import("dvui.zig");
pub const backend = @import("backend.zig");

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
