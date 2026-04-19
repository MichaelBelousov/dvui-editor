const std = @import("std");

const assets = @import("assets");
const dvui = @import("dvui");
const icons = @import("icons");

const inkz_editor = @import("../root.zig");

const Tools = @This();

var removed_index: ?usize = null;
var insert_before_index: ?usize = null;
var edit_layer_id: ?u64 = null;
var prev_layer_count: usize = 0;
var max_split_ratio: f32 = 0.4;

/// In-flight primary-button gesture for the active file's layer list (reorder / click / rename).
/// Not stored in `dvui.data`: a single path at end of `drawLayers` processes events after rename `textEntry`.
const LayerRowGesture = struct {
    file_id: u64,
    press_idx: usize,
    press_p: dvui.Point.Physical,
    drag_branch: ?usize,
    moved: bool,
    reorder_drag: bool,
};
var layer_row_gesture: ?LayerRowGesture = null;

/// Filled while the layer rename text entry exists so `processLayerTreePointerEvents` can skip those hits.
var layer_rename_hit_te_id: ?dvui.Id = null;
var layer_rename_hit_rect: ?dvui.Rect.Physical = null;

layers_rect: ?dvui.Rect.Physical = null,
/// Visible clip of the layer list (scroll container content rect). Rows can have screen rects that
/// extend below this when scrolled; without gating, those rects overlap the palettes pane and steal hover/input.
layers_scroll_viewport_rect: ?dvui.Rect.Physical = null,

pub fn init() Tools {
    return .{};
}

pub fn draw(self: *Tools) !void {
    _ = self;
    drawTools() catch {};
}

pub fn layersHovered(self: *Tools) bool {
    const mp = dvui.currentWindow().mouse_pt;
    if (self.layers_scroll_viewport_rect) |vr| {
        if (!vr.contains(mp)) return false;
    }
    if (self.layers_rect) |rect| {
        return rect.contains(mp);
    }
    return false;
}

pub fn drawTools() !void {
    const toolbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .expand = .none,
        .gravity_x = 0.5,
        .padding = .{ .h = 10.0, .w = 4.0, .x = 4.0, .y = 4.0 },
    });
    defer toolbox.deinit();
    // for (0..std.meta.fields(inkz_editor.Editor.Tools.Tool).len) |i| {
    //     const tool: inkz_editor.Editor.Tools.Tool = @enumFromInt(i);
    //     const id_extra = i;

    //     const selected = inkz_editor.editor.tools.current == tool;

    //     var color = dvui.themeGet().color(.control, .fill_hover);
    //     if (inkz_editor.editor.colors.file_tree_palette) |*palette| {
    //         color = palette.getDVUIColor(i);
    //     }

    //     const sprite = switch (tool) {
    //         .pointer => inkz_editor.editor.atlas.data.sprites[inkz_editor.atlas.sprites.cursor_default],
    //         .pencil => inkz_editor.editor.atlas.data.sprites[inkz_editor.atlas.sprites.pencil_default],
    //         .eraser => inkz_editor.editor.atlas.data.sprites[inkz_editor.atlas.sprites.eraser_default],
    //         .bucket => inkz_editor.editor.atlas.data.sprites[inkz_editor.atlas.sprites.bucket_default],
    //         .selection => inkz_editor.editor.atlas.data.sprites[inkz_editor.atlas.sprites.selection_default],
    //     };
    //     var button: dvui.ButtonWidget = undefined;
    //     button.init(@src(), .{}, .{
    //         .expand = .none,
    //         .min_size_content = .{ .w = 40, .h = 40 },
    //         .id_extra = id_extra,
    //         .background = true,
    //         .corner_radius = dvui.Rect.all(1000),
    //         .color_fill = if (selected) dvui.themeGet().color(.content, .fill) else .transparent,
    //         .color_fill_hover = dvui.themeGet().color(.content, .fill).lighten(if (dvui.themeGet().dark) 10.0 else -10.0),
    //         .box_shadow = if (selected) .{
    //             .color = .black,
    //             .offset = .{ .x = -2.5, .y = 2.5 },
    //             .fade = 4.0,
    //             .alpha = 0.25,
    //         } else null,
    //         .padding = .all(0),
    //         //.border = dvui.Rect.all(1.0),
    //         //.color_border = if (selected) color else dvui.themeGet().color(.control, .fill),
    //     });
    //     defer button.deinit();

    //     inkz_editor.editor.tools.drawTooltip(tool, button.data().rectScale().r, id_extra) catch {};

    //     if (button.hovered()) {
    //         button.data().options.color_border = color;
    //     }

    //     const size: dvui.Size = dvui.imageSize(inkz_editor.editor.atlas.source) catch .{ .w = 0, .h = 0 };

    //     const uv = dvui.Rect{
    //         .x = @as(f32, @floatFromInt(sprite.source[0])) / size.w,
    //         .y = @as(f32, @floatFromInt(sprite.source[1])) / size.h,
    //         .w = @as(f32, @floatFromInt(sprite.source[2])) / size.w,
    //         .h = @as(f32, @floatFromInt(sprite.source[3])) / size.h,
    //     };

    //     button.processEvents();
    //     button.drawBackground();

    //     var rs = button.data().contentRectScale();

    //     const width = @as(f32, @floatFromInt(sprite.source[2])) * rs.s;
    //     const height = @as(f32, @floatFromInt(sprite.source[3])) * rs.s;

    //     rs.r.x = @round(rs.r.x + (rs.r.w - width) / 2.0);
    //     rs.r.y = @round(rs.r.y + (rs.r.h - height) / 2.0);
    //     rs.r.w = width;
    //     rs.r.h = height;

    //     dvui.renderImage(inkz_editor.editor.atlas.source, rs, .{
    //         .uv = uv,
    //         .fade = 0.0,
    //     }) catch {
    //         dvui.log.err("Failed to render image", .{});
    //     };

    //     if (button.clicked()) {
    //         inkz_editor.editor.tools.set(tool);
    //     }
    // }
}
