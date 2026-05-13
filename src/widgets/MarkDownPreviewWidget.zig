const std = @import("std");

const dvui = @import("dvui");

const dvui_editor = @import("../root.zig");
const md_parse = @import("../md/cmark_parse.zig");
const render_ast = @import("../md/render_ast.zig");

pub const MarkDownPreviewWidget = @This();

file: *dvui_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *dvui_editor.Internal.TextFile) MarkDownPreviewWidget {
    _ = src;
    return .{ .file = file };
}

pub fn deinit(_: MarkDownPreviewWidget) void {}

pub fn processEvents(self: *MarkDownPreviewWidget) void {
    const file = self.file;
    const raw = file.content;
    // backing buffer may be larger than actual content; content ends at first null byte
    const content: []const u8 = raw[0 .. std.mem.indexOfScalar(u8, raw, 0) orelse raw.len];

    var wh = std.hash.Wyhash.init(0);
    wh.update(content);
    const h = wh.final();

    if (file.editor.markdown_preview_content_hash != h) {
        md_parse.freeCachedRoot(file.editor.markdown_preview_ast_root);
        file.editor.markdown_preview_ast_root = null;
        file.editor.markdown_preview_content_hash = h;
        if (md_parse.parseMarkdown(content)) |ast| {
            file.editor.markdown_preview_ast_root = @ptrCast(ast.root.n);
            _ = ast.extensions;
        }
    }

    var scroll = dvui.scrollArea(@src(), .{
        .scroll_info = &file.editor.markdown_preview_scroll,
        .horizontal_bar = .auto_overlay,
        .vertical_bar = .auto_overlay,
    }, .{
        .expand = .both,
        .margin = dvui.Rect.all(4),
        .corner_radius = dvui.Rect.all(5),
        .border = dvui.Rect.all(1),
        .padding = dvui.Rect.all(6),
        .background = true,
        .color_fill = dvui.themeGet().fill,
        .style = .content,
        .id_extra = self.file.id,
    });
    defer scroll.deinit();

    if (file.editor.markdown_preview_ast_root) |rp| {
        var v = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .horizontal,
            .padding = .{ .x = 8, .y = 8, .w = 8, .h = 8 },
        });
        defer v.deinit();
        const root: md_parse.Node = .{ .n = @ptrCast(@alignCast(rp)) };
        const base_dir = std.fs.path.dirname(self.file.path) orelse ".";
        render_ast.renderDocument(root, .{
            .image_base_dir = base_dir,
            .io = dvui_editor.app.io,
        });
    } else {
        dvui.labelNoFmt(
            @src(),
            "Could not parse markdown.",
            .{},
            .{
                .expand = .both,
                .gravity_x = 0.5,
                .gravity_y = 0.5,
                .color_text = dvui.themeGet().color(.err, .text).opacity(0.85),
                .id_extra = self.file.id,
            },
        );
    }
}
