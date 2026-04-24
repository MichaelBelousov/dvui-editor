const std = @import("std");
const Io = std.Io;

const Core = @import("mach").Core;
const dvui = @import("dvui");
const nfd = @import("nfd");

const inkz_editor = @import("../root.zig");
const App = inkz_editor.App;
const Editor = inkz_editor.Editor;
const Packer = inkz_editor.Packer;
pub const files = @import("files.zig");
pub const project = @import("project.zig");
pub const settings = @import("settings.zig");
pub const Tools = @import("tools.zig");

pub const Explorer = @This();

// pub const animations = @import("animations.zig");
// pub const keyframe_animations = @import("keyframe_animations.zig");
tools: Tools = .{},
pane: Pane = .files,
paned: *inkz_editor.dvui.PanedWidget = undefined,
scroll_info: dvui.ScrollInfo = .{
    .horizontal = .auto,
},
rect: dvui.Rect = .{},
open_branches: std.AutoHashMap(dvui.Id, void) = undefined,
pinned_palettes: bool = false,
layers_ratio: f32 = 0.5,
animations_ratio: f32 = 0.5,
closed: bool = true,

pub const Pane = enum(u32) {
    files,
    tools,
    // sprites,
    // animations,
    // keyframe_animations,
    project,
    settings,
};

pub fn init() Explorer {
    return .{
        .open_branches = .init(inkz_editor.app.gpa),
    };
}

pub fn deinit(self: *Explorer) void {
    // TODO: Free memory
    self.open_branches.deinit();
}

pub fn title(pane: Pane, all_caps: bool) []const u8 {
    return switch (pane) {
        .files => if (all_caps) "FILES" else "Files",
        .tools => if (all_caps) "TOOLS" else "Tools",
        // .sprites => if (all_caps) "SPRITES" else "Sprites",
        // .animations => if (all_caps) "ANIMATIONS" else "Animations",
        // .keyframe_animations => if (all_caps) "KEYFRAME ANIMATIONS" else "Keyframe Animations",
        .project => if (all_caps) "PROJECT" else "Project",
        .settings => if (all_caps) "SETTINGS" else "Settings",
    };
}

pub fn close(explorer: *Explorer) void {
    explorer.paned.animateSplit(0.0, dvui.easing.outQuint);
    explorer.closed = true;
}

pub fn open(explorer: *Explorer) void {
    if (explorer.paned.collapsed()) return;

    if (inkz_editor.editor.settings.explorer_ratio > 0.0) {
        std.debug.print("Ratio: {any}\n", .{inkz_editor.editor.settings.explorer_ratio});
        explorer.paned.animateSplit(inkz_editor.editor.settings.explorer_ratio, dvui.easing.outBack);
    } else {
        explorer.paned.animateSplit(0.2, dvui.easing.outBack);
    }

    explorer.closed = false;
}

pub fn draw(explorer: *Explorer, io: std.Io, environ: *const std.process.Environ.Map) !dvui.App.Result {
    const vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .background = false,
    });
    defer vbox.deinit();

    explorer.rect = vbox.data().rect;

    try drawHeader(explorer);

    _ = dvui.spacer(@src(), .{});

    const pane_vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .background = false,
    });

    var scroll = dvui.scrollArea(@src(), .{ .scroll_info = &explorer.scroll_info, .horizontal_bar = .auto_overlay, .vertical_bar = .auto_overlay }, .{
        .expand = .both,
        .background = false,
    });

    switch (explorer.pane) {
        .files => try files.draw(io, environ),
        .settings => try settings.draw(),
        .project => try project.draw(),
        .tools => try explorer.tools.draw(),
        // else => {},
    }

    const vertical_scroll = scroll.si.offset(.vertical);
    const horizontal_scroll = scroll.si.offset(.horizontal);

    scroll.deinit();

    if (vertical_scroll > 0.0) {
        inkz_editor.dvui.drawEdgeShadow(pane_vbox.data().contentRectScale(), .top, .{});
    }

    if (explorer.scroll_info.virtual_size.h > explorer.scroll_info.viewport.h) {
        inkz_editor.dvui.drawEdgeShadow(pane_vbox.data().contentRectScale(), .bottom, .{});
    }

    pane_vbox.deinit();

    if (explorer.scroll_info.virtual_size.w > explorer.scroll_info.viewport.w) {
        inkz_editor.dvui.drawEdgeShadow(vbox.data().contentRectScale(), .right, .{});
    }

    if (horizontal_scroll > 0.0) {
        inkz_editor.dvui.drawEdgeShadow(vbox.data().contentRectScale(), .left, .{});
    }

    return .ok;
}

pub fn hovered(explorer: *Explorer) bool {
    return inkz_editor.dvui.hovered(explorer.paned.data());
}

pub fn drawHeader(explorer: *Explorer) !void {
    const header_title = title(explorer.pane, true);

    dvui.labelNoFmt(@src(), header_title, .{}, .{ .font = dvui.Font.theme(.title).larger(-3.0).withWeight(.bold) });
}
