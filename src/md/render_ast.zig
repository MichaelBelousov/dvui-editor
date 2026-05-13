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

/// Plain UTF-8 for `TextLayoutWidget.addLink`; nested emph/strong in the label lose per-span styling.
fn appendInlinePlainText(arena: std.mem.Allocator, n: md.Node, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    var cur: ?md.Node = n.firstChild();
    while (cur) |x| : (cur = x.nextSibling()) {
        switch (x.nodeType()) {
            md.c.CMARK_NODE_TEXT => {
                if (x.literal()) |t| try out.appendSlice(arena, t);
            },
            md.c.CMARK_NODE_SOFTBREAK => {
                try out.append(arena, ' ');
            },
            md.c.CMARK_NODE_LINEBREAK => {
                try out.append(arena, '\n');
            },
            md.c.CMARK_NODE_CODE => {
                if (x.literal()) |t| try out.appendSlice(arena, t);
            },
            md.c.CMARK_NODE_LINK => {
                try appendInlinePlainText(arena, x, out);
            },
            md.c.CMARK_NODE_IMAGE => {
                try out.appendSlice(arena, "![");
                try appendInlinePlainText(arena, x, out);
                try out.append(arena, ']');
                if (x.linkUrl()) |u| {
                    try out.append(arena, '(');
                    try out.appendSlice(arena, u);
                    try out.append(arena, ')');
                }
            },
            else => {
                if (isStrikethrough(x)) {
                    try appendInlinePlainText(arena, x, out);
                } else if (x.firstChild()) |_| {
                    try appendInlinePlainText(arena, x, out);
                } else if (x.literal()) |t| {
                    try out.appendSlice(arena, t);
                }
            },
        }
    }
}

fn linkLabelPlainText(link: md.Node, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(arena);
    try appendInlinePlainText(arena, link, &list);
    return try list.toOwnedSlice(arena);
}

/// `span` carries inherited font/color down into inline content.
/// Only `.font` and `.color_text` are meaningful here.
fn renderInlines(tl: *dvui.TextLayoutWidget, n: md.Node, span: dvui.Options) void {
    var cur: ?md.Node = n.firstChild();
    while (cur) |x| : (cur = x.nextSibling()) {
        switch (x.nodeType()) {
            md.c.CMARK_NODE_TEXT => {
                if (x.literal()) |t| tl.addText(t, .{ .font = span.font, .color_text = span.color_text });
            },
            md.c.CMARK_NODE_SOFTBREAK => {
                tl.addText(" ", .{});
            },
            md.c.CMARK_NODE_LINEBREAK => {
                tl.addText("\n", .{});
            },
            md.c.CMARK_NODE_CODE => {
                if (x.literal()) |t| {
                    tl.addText(t, .{
                        .font = dvui.Font.theme(.mono).larger(-1),
                        .color_text = dvui.themeGet().color(.control, .text).opacity(0.9),
                    });
                }
            },
            md.c.CMARK_NODE_EMPH => {
                if (x.firstChild()) |_| {
                    const f = span.fontGet().withStyle(.italic);
                    renderInlines(tl, x, span.override(.{ .font = f }));
                }
            },
            md.c.CMARK_NODE_STRONG => {
                if (x.firstChild()) |_| {
                    const f = span.fontGet().withWeight(.bold);
                    renderInlines(tl, x, span.override(.{ .font = f }));
                }
            },
            md.c.CMARK_NODE_LINK => {
                const link_font = span.fontGet().withUnderline(.{});
                const link_color = dvui.themeGet().focus;
                const link_opts = span.override(.{ .font = link_font, .color_text = link_color });
                const url = x.linkUrl() orelse "";
                if (url.len == 0) {
                    if (x.firstChild()) |_| renderInlines(tl, x, link_opts);
                } else {
                    const arena = dvui.currentWindow().arena();
                    if (linkLabelPlainText(x, arena)) |display| {
                        tl.addLink(.{
                            .url = url,
                            .text = if (display.len == 0) null else display,
                        }, link_opts);
                    } else |_| {
                        if (x.firstChild()) |_| renderInlines(tl, x, link_opts);
                    }
                }
            },
            md.c.CMARK_NODE_IMAGE => {
                tl.addText("![", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.6) });
                if (x.firstChild()) |_| renderInlines(tl, x, span);
                tl.addText("]", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.6) });
                if (x.linkUrl()) |u| {
                    tl.addText("(", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.4) });
                    tl.addText(u, .{ .font = dvui.Font.theme(.mono).larger(-2), .color_text = dvui.themeGet().color(.control, .text).opacity(0.55) });
                    tl.addText(")", .{ .color_text = dvui.themeGet().color(.control, .text).opacity(0.4) });
                }
            },
            md.c.CMARK_NODE_HTML_INLINE => {
                if (x.literal()) |t| tl.addText(t, .{
                    .font = dvui.Font.theme(.mono).larger(-2),
                    .color_text = dvui.themeGet().color(.err, .text),
                });
            },
            md.c.CMARK_NODE_FOOTNOTE_REFERENCE => {
                if (x.literal()) |t| {
                    const fn_font = dvui.Font.theme(.mono).larger(-2);
                    const fn_color = dvui.themeGet().focus.opacity(0.8);
                    tl.addText("[^", .{ .font = fn_font, .color_text = fn_color });
                    tl.addText(t, .{ .font = fn_font, .color_text = fn_color });
                    tl.addText("]", .{ .font = fn_font, .color_text = fn_color });
                }
            },
            else => {
                if (isStrikethrough(x)) {
                    const strike_font = span.fontGet().withStrike(.{});
                    const strike_color = dvui.themeGet().color(.control, .text).opacity(0.5);
                    renderInlines(tl, x, .{ .font = strike_font, .color_text = strike_color });
                } else if (x.firstChild()) |_| {
                    renderInlines(tl, x, span);
                } else if (x.literal()) |t| {
                    tl.addText(t, .{ .font = span.font, .color_text = span.color_text });
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
            var outer = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .expand = .horizontal,
                .margin = .{ .x = 4, .y = 4, .w = 4, .h = 4 },
                .id_extra = ids.next(),
            });
            defer outer.deinit();

            // Left accent bar
            _ = dvui.spacer(@src(), .{
                .min_size_content = .{ .w = 3, .h = 0 },
                .expand = .vertical,
                .background = true,
                .color_fill = dvui.themeGet().color(.highlight, .fill).opacity(0.75),
                .corner_radius = dvui.Rect.all(2),
                .id_extra = ids.next(),
            });

            var content = dvui.box(@src(), .{ .dir = .vertical }, .{
                .expand = .horizontal,
                .padding = .{ .x = 10, .y = 4, .w = 0, .h = 4 },
                .id_extra = ids.next(),
            });
            defer content.deinit();

            var c = n.firstChild();
            while (c) |ch| : (c = ch.nextSibling()) renderBlock(ch, ids);
        },
        md.c.CMARK_NODE_LIST => {
            var it = n.firstChild();
            var idx: i32 = n.listStart();
            // Fixed column width — wide enough for "99." in the body font
            const col_w = dvui.Font.theme(.body).sizeM(2.2, 0).w;
            while (it) |item_node| : (it = item_node.nextSibling()) {
                if (item_node.nodeType() != md.c.CMARK_NODE_ITEM) {
                    renderBlock(item_node, ids);
                    continue;
                }
                var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
                    .expand = .horizontal,
                    .margin = .{ .y = 1 },
                    .id_extra = ids.next(),
                });
                defer row.deinit();

                var buf: [24]u8 = undefined;
                const is_task = n.listKind() == .ul and item_node.taskListItemChecked();
                const bullet_str: []const u8 = if (is_task)
                    "✓"
                else switch (n.listKind()) {
                    .ul => "•",
                    .ol => std.fmt.bufPrint(&buf, "{d}.", .{idx}) catch "?",
                };
                if (n.listKind() == .ol) idx += 1;

                const bullet_color = if (is_task)
                    dvui.themeGet().color(.highlight, .fill)
                else
                    dvui.themeGet().color(.control, .text).opacity(0.45);

                // Fixed-width column; spacer pushes bullet to the right edge
                {
                    var pb = dvui.box(@src(), .{ .dir = .horizontal }, .{
                        .min_size_content = .{ .w = col_w, .h = 0 },
                        .gravity_y = 0,
                        .id_extra = ids.next(),
                    });
                    _ = dvui.spacer(@src(), .{ .expand = .horizontal, .id_extra = ids.next() });
                    dvui.labelNoFmt(@src(), bullet_str, .{}, .{
                        .gravity_y = 0,
                        .color_text = bullet_color,
                        .id_extra = ids.next(),
                    });
                    pb.deinit();
                }

                // Gap between bullet column and content
                _ = dvui.spacer(@src(), .{ .min_size_content = .{ .w = 5, .h = 0 }, .id_extra = ids.next() });

                var col = dvui.box(@src(), .{ .dir = .vertical }, .{
                    .expand = .horizontal,
                    .id_extra = ids.next(),
                });
                defer col.deinit();

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
                .margin = .{ .y = 6 },
                .background = true,
                .color_fill = dvui.themeGet().color(.window, .fill).opacity(0.9),
                .corner_radius = dvui.Rect.all(6),
                .border = dvui.Rect.all(1),
                .color_border = dvui.themeGet().border.opacity(0.35),
                .id_extra = ids.next(),
            });
            defer outer.deinit();

            if (info.len > 0) {
                var hdr = dvui.box(@src(), .{ .dir = .horizontal }, .{
                    .expand = .horizontal,
                    .padding = .{ .x = 10, .y = 5, .w = 10, .h = 5 },
                    .background = true,
                    .color_fill = dvui.themeGet().border.opacity(0.12),
                    .id_extra = ids.next(),
                });
                defer hdr.deinit();
                var tl_i = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .id_extra = ids.next() });
                tl_i.addText(info, .{
                    .font = dvui.Font.theme(.mono).larger(-2).withWeight(.bold),
                    .color_text = dvui.themeGet().color(.control, .text).opacity(0.55),
                });
                tl_i.deinit();
            }

            var tl_c = dvui.textLayout(@src(), .{}, .{
                .expand = .horizontal,
                .padding = .{ .x = 10, .y = 8, .w = 10, .h = 8 },
                .id_extra = ids.next(),
            });
            defer tl_c.deinit();
            tl_c.addText(code, .{ .font = dvui.Font.theme(.mono).larger(-1) });
        },
        md.c.CMARK_NODE_HTML_BLOCK => {
            if (n.literal()) |h| {
                var tl = dvui.textLayout(@src(), .{}, .{
                    .expand = .horizontal,
                    .margin = .{ .y = 2 },
                    .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
                    .background = true,
                    .color_fill = dvui.themeGet().color(.err, .fill).opacity(0.08),
                    .id_extra = ids.next(),
                });
                defer tl.deinit();
                tl.addText(h, .{
                    .font = dvui.Font.theme(.mono).larger(-2),
                    .color_text = dvui.themeGet().color(.err, .text).opacity(0.85),
                });
            }
        },
        md.c.CMARK_NODE_PARAGRAPH => {
            var tl = dvui.textLayout(@src(), .{}, .{
                .expand = .horizontal,
                .margin = .{ .y = 4, .h = 4 },
                .id_extra = ids.next(),
            });
            defer tl.deinit();
            renderInlines(tl, n, .{});
        },
        md.c.CMARK_NODE_HEADING => {
            const level = @max(1, @min(6, n.headingLevel()));
            const size_bump: f32 = switch (level) {
                1 => 9,
                2 => 6,
                3 => 3,
                4 => 1,
                else => 0,
            };
            const top_margin: f32 = switch (level) {
                1 => 18,
                2 => 14,
                3 => 10,
                else => 7,
            };
            const heading_font = dvui.Font.theme(.heading).larger(size_bump - 2).withWeight(.bold);

            var tl = dvui.textLayout(@src(), .{}, .{
                .expand = .horizontal,
                .margin = .{ .y = top_margin, .h = 2 },
                .font = heading_font,
                .id_extra = ids.next(),
            });
            defer tl.deinit();
            renderInlines(tl, n, .{});
        },
        md.c.CMARK_NODE_THEMATIC_BREAK => {
            _ = dvui.separator(@src(), .{
                .expand = .horizontal,
                .margin = .{ .y = 10, .h = 10 },
                .color_fill = dvui.themeGet().border.opacity(0.45),
                .id_extra = ids.next(),
            });
        },
        md.c.CMARK_NODE_FOOTNOTE_DEFINITION => {
            if (n.literal()) |name| {
                var tl = dvui.textLayout(@src(), .{}, .{
                    .expand = .horizontal,
                    .margin = .{ .y = 4 },
                    .id_extra = ids.next(),
                });
                const fn_font = dvui.Font.theme(.mono).larger(-1);
                const fn_color = dvui.themeGet().focus.opacity(0.8);
                tl.addText("[^", .{ .font = fn_font, .color_text = fn_color });
                tl.addText(name, .{ .font = fn_font, .color_text = fn_color });
                tl.addText("]: ", .{ .font = fn_font, .color_text = fn_color });
                tl.deinit();
            }
            var c = n.firstChild();
            while (c) |ch| : (c = ch.nextSibling()) renderBlock(ch, ids);
        },
        else => {
            if (isTable(n)) {
                var outer = dvui.box(@src(), .{ .dir = .vertical }, .{
                    .expand = .horizontal,
                    .margin = .{ .y = 6 },
                    .background = true,
                    .color_fill = dvui.themeGet().color(.window, .fill).opacity(0.3),
                    .corner_radius = dvui.Rect.all(4),
                    .border = dvui.Rect.all(1),
                    .color_border = dvui.themeGet().border.opacity(0.3),
                    .id_extra = ids.next(),
                });
                defer outer.deinit();

                var row_idx: usize = 0;
                var c = n.firstChild();
                while (c) |row| : (c = row.nextSibling()) {
                    if (!isTableRow(row)) continue;
                    const header = row.tableRowIsHeader();
                    const even = (row_idx % 2) == 0;
                    row_idx += 1;

                    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
                        .expand = .horizontal,
                        .background = true,
                        .color_fill = if (header)
                            dvui.themeGet().color(.highlight, .fill).opacity(0.2)
                        else if (even)
                            dvui.themeGet().color(.window, .fill).opacity(0.0)
                        else
                            dvui.themeGet().color(.control, .fill).opacity(0.15),
                        .id_extra = ids.next(),
                    });
                    defer hbox.deinit();

                    var cell = row.firstChild();
                    while (cell) |cl| : (cell = cl.nextSibling()) {
                        if (!isTableCell(cl)) continue;
                        var cell_box = dvui.box(@src(), .{ .dir = .vertical }, .{
                            .expand = .ratio,
                            .padding = .{ .x = 8, .y = 5, .w = 8, .h = 5 },
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
