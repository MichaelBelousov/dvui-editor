const std = @import("std");
const Io = std.Io;

const inkz_editor = @import("../root.zig");

const TextFile = @This();

id: u64 = 0,
path: []const u8 = "",
// TODO: Use less naive datastructure, this will always read full file content into memory!
content: []const u8 = "",
editor: EditorData = .{},

pub const EditorData = struct {
    grouping: u64 = 0,
};

pub const InitOptions = struct {};

pub fn fromPath(path: []const u8) !TextFile {
    const io = inkz_editor.app.io;
    const gpa = inkz_editor.app.gpa;
    const content = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    const path_copy = try gpa.dupe(u8, path);
    return .{
        .id = inkz_editor.editor.newFileID(),
        .path = path_copy,
        .content = content,
    };
}

pub fn deinit(self: *TextFile) void {
    const gpa = inkz_editor.app.gpa;
    gpa.free(self.path);
    gpa.free(self.content);
}
