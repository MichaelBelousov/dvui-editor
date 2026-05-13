const std = @import("std");

const dvui = @import("dvui");

const md = @import("cmark_parse.zig");

fn isTable(n: md.Node) bool {
    return std.mem.eql(u8, n.typeString(), "table");
}
fn isTableRow(n: md.Node) bool {
    return std.mem.eql(u8, n.typeString(), "table_row");
}
fn isTableCell(n: md.Node) bool {
    return std.mem.eql(u8, n.typeString(), "table_cell");
}
fn isStrikethrough(n: md.Node) bool {
    return std.mem.eql(u8, n.typeString(), "strikethrough");
}

/// dvui ids derive from @src(); repeated layouts in loops/recursion need unique `.id_extra`.
const IdGen = struct {
    n: usize = 0,
    fn next(g: *IdGen) usize {
        g.n += 1;
        return g.n;
    }
};

fn renderInlines(tl: anytype, n: md.Node) void {
    var cur: ?md.Node = n.firstChild();
    while (cur) |x| : (cur = x.nextSibling()) {
        switch (x.nodeType()) {
            md.c.CMARK_NODE_TEXT => {
                if (x.literal()) |t| tl.addText(t, .{});
            },
            md.c.CMARK_NODE_SOFTBREAK => {
                tl.addText(" ", .{});
            },
            md.c.CMARK_NODE_LINEBREAK => {
                tl.addText("\n", .{});
            },
            md.c.CMARK_NODE_CODE => {
                if (x.literal()) |t| {
                    tl.addText(t, .{ .font = dvui.Font.theme(.mono) });
                }
            },
            md.c.CMARK_NODE_EMPH => {
                tl.addText("_", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.75) });
                if (x.firstChild()) |_| renderInlines(tl, x);
                tl.addText("_", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.75) });
            },
            md.c.CMARK_NODE_STRONG => {
                tl.addText("**", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.75) });
                if (x.firstChild()) |_| renderInlines(tl, x);
                tl.addText("**", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.75) });
            },
            md.c.CMARK_NODE_LINK => {
                if (x.firstChild()) |_| renderInlines(tl, x);
                if (x.linkUrl()) |u| {
                    tl.addText(" (", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.65) });
                    tl.addText(u, .{ .font = dvui.Font.theme(.mono).larger(-1), .color_text = dvui.themeGet().color(.control, .text).opacity(0.85) });
                    tl.addText(")", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.65) });
                }
            },
            md.c.CMARK_NODE_IMAGE => {
                tl.addText("![", .{});
                if (x.firstChild()) |_| renderInlines(tl, x);
                tl.addText("]", .{});
                if (x.linkUrl()) |u| {
                    tl.addText("(", .{});
                    tl.addText(u, .{ .font = dvui.Font.theme(.mono).larger(-1) });
                    tl.addText(")", .{});
                }
            },
            md.c.CMARK_NODE_HTML_INLINE => {
                if (x.literal()) |t| tl.addText(t, .{ .font = dvui.Font.theme(.mono).larger(-1), .color_text = dvui.themeGet().color(.err, .text) });
            },
            md.c.CMARK_NODE_FOOTNOTE_REFERENCE => {
                if (x.literal()) |t| {
                    tl.addText("[^", .{ .font = dvui.Font.theme(.mono).larger(-1) });
                    tl.addText(t, .{ .font = dvui.Font.theme(.mono).larger(-1) });
                    tl.addText("]", .{ .font = dvui.Font.theme(.mono).larger(-1) });
                }
            },
            else => {
                if (isStrikethrough(x)) {
                    if (x.literal()) |t| {
                        tl.addText(t, .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.45) });
                    } else if (x.firstChild()) |_| {
                        tl.addText("~~", .{});
                        renderInlines(tl, x);
                        tl.addText("~~", .{});
                    }
                } else if (x.firstChild()) |_| {
                    renderInlines(tl, x);
                } else if (x.literal()) |t| {
                    tl.addText(t, .{});
                }
            },
        }
    }
}

fn renderBlock(n: md.Node, ids: *IdGen) void {
    const t = n.nodeType();
    switch (t) {
        md.c.CMARK_NODE_DOCUMENT => {
            var c = n.firstChild();
            while (c) |ch| : (c = ch.nextSibling()) renderBlock(ch, ids);
        },
        md.c.CMARK_NODE_BLOCK_QUOTE => {
            var b = dvui.box(@src(), .{ .dir = .vertical }, .{
                .expand = .horizontal,
                .margin = .{ .x = 6, .y = 2, .w = 6, .h = 2 },
                .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
                .background = true,
                .color_fill = dvui.themeGet().color(.control, .fill).opacity(0.35),
                .corner_radius = dvui.Rect.all(4),
                .id_extra = ids.next(),
            });
            defer b.deinit();
            var c = n.firstChild();
            while (c) |ch| : (c = ch.nextSibling()) renderBlock(ch, ids);
        },
        md.c.CMARK_NODE_LIST => {
            var it = n.firstChild();
            var idx: i32 = n.listStart();
            while (it) |item_node| : (it = item_node.nextSibling()) {
                if (item_node.nodeType() != md.c.CMARK_NODE_ITEM) {
                    renderBlock(item_node, ids);
                    continue;
                }
                var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
                    .expand = .horizontal,
                    .margin = .{ .y = 2 },
                    .id_extra = ids.next(),
                });
                defer row.deinit();

                var buf: [24]u8 = undefined;
                const prefix_text: []const u8 = switch (n.listKind()) {
                    .ul => "• ",
                    .ol => std.fmt.bufPrint(&buf, "{d}. ", .{idx}) catch "• ",
                };
                if (n.listKind() == .ol) idx += 1;

                var tl_pre = dvui.textLayout(@src(), .{}, .{ .expand = .none, .gravity_y = 0, .id_extra = ids.next() });
                tl_pre.addText(prefix_text, .{});
                tl_pre.deinit();

                var col = dvui.box(@src(), .{ .dir = .vertical }, .{
                    .expand = .horizontal,
                    .id_extra = ids.next(),
                });
                defer col.deinit();

                if (n.listKind() == .ul and item_node.taskListItemChecked()) {
                    var tlx = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .id_extra = ids.next() });
                    tlx.addText("[x] ", .{ .font = dvui.Font.theme(.mono).larger(-1) });
                    tlx.deinit();
                }

                var sub = item_node.firstChild();
                while (sub) |s| : (sub = s.nextSibling()) {
                    renderBlock(s, ids);
                }
            }
        },
        md.c.CMARK_NODE_ITEM => {
            var c = n.firstChild();
            while (c) |ch| : (c = ch.nextSibling()) renderBlock(ch, ids);
        },
        md.c.CMARK_NODE_CODE_BLOCK => {
            const info = n.fenceInfo() orelse "";
            const code = n.literal() orelse "";
            var outer = dvui.box(@src(), .{ .dir = .vertical }, .{
                .expand = .horizontal,
                .margin = .{ .y = 4 },
                .padding = .{ .x = 8, .y = 6, .w = 8, .h = 6 },
                .background = true,
                .color_fill = dvui.themeGet().color(.window, .fill).opacity(0.9),
                .corner_radius = dvui.Rect.all(4),
                .id_extra = ids.next(),
            });
            defer outer.deinit();
            if (info.len > 0) {
                var tl_i = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .id_extra = ids.next() });
                tl_i.addText(info, .{ .font = dvui.Font.theme(.mono).larger(-2), .color_text = dvui.themeGet().color(.control, .text).opacity(0.7) });
                tl_i.deinit();
            }
            var tl_c = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .id_extra = ids.next() });
            defer tl_c.deinit();
            tl_c.addText(code, .{ .font = dvui.Font.theme(.mono).larger(-1) });
        },
        md.c.CMARK_NODE_HTML_BLOCK => {
            if (n.literal()) |h| {
                var tl = dvui.textLayout(@src(), .{}, .{
                    .expand = .horizontal,
                    .margin = .{ .y = 2 },
                    .id_extra = ids.next(),
                });
                defer tl.deinit();
                tl.addText(h, .{ .font = dvui.Font.theme(.mono).larger(-2), .color_text = dvui.themeGet().color(.err, .text).opacity(0.85) });
            }
        },
        md.c.CMARK_NODE_PARAGRAPH => {
            var tl = dvui.textLayout(@src(), .{}, .{
                .expand = .horizontal,
                .margin = .{ .y = 3 },
                .id_extra = ids.next(),
            });
            defer tl.deinit();
            renderInlines(tl, n);
        },
        md.c.CMARK_NODE_HEADING => {
            const level = @max(1, @min(6, n.headingLevel()));
            const bump: f32 = @floatFromInt(8 - level);
            var tl = dvui.textLayout(@src(), .{}, .{
                .expand = .horizontal,
                .margin = .{ .y = 4 },
                .font = dvui.Font.theme(.title).larger(-4 + bump),
                .id_extra = ids.next(),
            });
            defer tl.deinit();
            renderInlines(tl, n);
        },
        md.c.CMARK_NODE_THEMATIC_BREAK => {
            _ = dvui.spacer(@src(), .{ .min_size_content = .{ .w = 0, .h = 8 }, .id_extra = ids.next() });
        },
        md.c.CMARK_NODE_FOOTNOTE_DEFINITION => {
            if (n.literal()) |name| {
                var tl = dvui.textLayout(@src(), .{}, .{
                    .expand = .horizontal,
                    .margin = .{ .y = 4 },
                    .id_extra = ids.next(),
                });
                tl.addText("[^", .{ .font = dvui.Font.theme(.mono).larger(-1) });
                tl.addText(name, .{ .font = dvui.Font.theme(.mono).larger(-1) });
                tl.addText("]: ", .{ .font = dvui.Font.theme(.mono).larger(-1) });
                tl.deinit();
            }
            var c = n.firstChild();
            while (c) |ch| : (c = ch.nextSibling()) renderBlock(ch, ids);
        },
        else => {
            if (isTable(n)) {
                var c = n.firstChild();
                while (c) |row| : (c = row.nextSibling()) {
                    if (!isTableRow(row)) continue;
                    const header = row.tableRowIsHeader();
                    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
                        .expand = .horizontal,
                        .margin = .{ .y = 1 },
                        .padding = .{ .x = 2, .y = 2, .w = 2, .h = 2 },
                        .background = header,
                        .color_fill = if (header) dvui.themeGet().color(.control, .fill).opacity(0.5) else dvui.themeGet().color(.window, .fill).opacity(0.25),
                        .id_extra = ids.next(),
                    });
                    defer hbox.deinit();
                    var cell = row.firstChild();
                    while (cell) |cl| : (cell = cl.nextSibling()) {
                        if (!isTableCell(cl)) continue;
                        var cell_box = dvui.box(@src(), .{ .dir = .vertical }, .{
                            .expand = .ratio,
                            .padding = .{ .x = 4, .y = 2, .w = 4, .h = 2 },
                            .id_extra = ids.next(),
                        });
                        defer cell_box.deinit();
                        var sub = cl.firstChild();
                        while (sub) |s| : (sub = s.nextSibling()) renderBlock(s, ids);
                    }
                }
            } else {
                var c = n.firstChild();
                while (c) |ch| : (c = ch.nextSibling()) renderBlock(ch, ids);
            }
        },
    }
}

pub fn renderDocument(root: md.Node) void {
    var ids: IdGen = .{};
    renderBlock(root, &ids);
}
