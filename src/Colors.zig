const std = @import("std");
const inkz_editor = @import("root.zig");

const Self = @This();

primary: [4]u8 = .{ 255, 255, 255, 255 },
secondary: [4]u8 = .{ 0, 0, 0, 255 },
height: u8 = 0,
palette: ?inkz_editor.Internal.Palette = null,
file_tree_palette: ?inkz_editor.Internal.Palette = null,
