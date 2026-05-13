const std = @import("std");
const Io = std.Io;

const dvui = @import("dvui");

const dvui_editor = @import("../root.zig");
const md_parse = @import("../md/cmark_parse.zig");
const TextEditWidget = @import("../widgets/TextEditWidget.zig");

const TextFile = @This();

id: u64 = undefined,
path: []const u8 = undefined,
// TODO: Use less naive datastructure, this will always read full file content into memory!
content: []u8 = undefined,
lines: u64 = undefined,
editor: EditorData = .{},

pub const EditorData = struct {
    workspace: *dvui_editor.Editor.Workspace = undefined,
    grouping: u64 = 0,
    text_edit_widget: TextEditWidget = .{},
    markdown_preview_scroll: dvui.ScrollInfo = .{},
    markdown_preview_content_hash: u64 = std.math.maxInt(u64),
    markdown_preview_ast_root: ?*anyopaque = null,
};

pub const InitOptions = struct {};

pub fn fromPath(path: []const u8) !TextFile {
    const io = dvui_editor.app.io;
    const gpa = dvui_editor.app.gpa;
    const content = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    const path_copy = try gpa.dupe(u8, path);
    const lines = std.mem.count(u8, content, "\n");
    return .{
        .id = dvui_editor.editor.newFileID(),
        .path = path_copy,
        .content = content,
        .lines = lines,
    };
}

pub fn saveAsync(self: *const TextFile) !void {
    const io = dvui_editor.app.io;
    const data = self.content[0 .. std.mem.indexOfScalar(u8, self.content, 0) orelse self.content.len];
    try Io.Dir.cwd().writeFile(io, .{
        .data = data,
        .sub_path = self.path,
        .flags = .{},
    });
}

pub fn deinit(self: *TextFile) void {
    const gpa = dvui_editor.app.gpa;
    md_parse.freeCachedRoot(self.editor.markdown_preview_ast_root);
    self.editor.markdown_preview_ast_root = null;
    gpa.free(self.path);
    gpa.free(self.content);
}
