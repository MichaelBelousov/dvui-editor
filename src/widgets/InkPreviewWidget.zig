const std = @import("std");
const dvui = @import("dvui");

const dvui_editor = @import("../root.zig");
const inkz = @import("inkz");

pub const InkPreviewWidget = @This();

file: *dvui_editor.Internal.TextFile = undefined,

pub fn init(src: std.builtin.SourceLocation, file: *dvui_editor.Internal.TextFile) InkPreviewWidget {
    _ = src;
    return .{ .file = file };
}

pub fn deinit(_: InkPreviewWidget) void {}

fn refreshTerminalState(file: *dvui_editor.Internal.TextFile) void {
    const story = file.editor.ink_preview_story orelse {
        file.editor.ink_preview_done = false;
        return;
    };
    // Only safe to call while the story is still advancing; once `done`, we stop touching `Story`
    // (avoids querying the runtime every frame after the story has ended).
    file.editor.ink_preview_done =
        story.currentChoices().len == 0 and !story.canContinue();
}

fn appendContOutput(gpa: std.mem.Allocator, file: *dvui_editor.Internal.TextFile) void {
    const story = file.editor.ink_preview_story orelse return;
    const chunk = story.cont() catch |err| {
        if (file.editor.ink_preview_err) |m| gpa.free(m);
        file.editor.ink_preview_err = std.fmt.allocPrint(gpa, "continue failed: {s}", .{@errorName(err)}) catch return;
        return;
    };
    defer gpa.free(chunk);
    if (chunk.len > 0) {
        const tr = &file.editor.ink_preview_transcript;
        if (tr.items.len > 0) {
            tr.appendSlice(gpa, "\n\n") catch return;
        }
        tr.appendSlice(gpa, chunk) catch return;
    }
    refreshTerminalState(file);
}

fn rebuildStory(self: *InkPreviewWidget, gpa: std.mem.Allocator, content: []const u8) void {
    const file = self.file;
    file.editor.ink_preview_done = false;

    if (file.editor.ink_preview_story) |story| {
        story.deinit();
        gpa.destroy(story);
        file.editor.ink_preview_story = null;
    }
    if (file.editor.ink_preview_err) |msg| {
        gpa.free(msg);
        file.editor.ink_preview_err = null;
    }
    file.editor.ink_preview_transcript.clearRetainingCapacity();

    const json = inkz.compiler.compile.compile(gpa, content) catch |err| {
        file.editor.ink_preview_err = std.fmt.allocPrint(gpa, "compile failed: {s}", .{@errorName(err)}) catch return;
        return;
    };
    defer gpa.free(json);

    const story_val = inkz.Story.initFromJson(gpa, json) catch |err| {
        file.editor.ink_preview_err = std.fmt.allocPrint(gpa, "story init failed: {s}", .{@errorName(err)}) catch return;
        return;
    };
    const story_ptr = gpa.create(inkz.Story) catch {
        var s = story_val;
        s.deinit();
        return;
    };
    story_ptr.* = story_val;
    file.editor.ink_preview_story = story_ptr;

    appendContOutput(gpa, file);
}

fn onChoice(self: *InkPreviewWidget, gpa: std.mem.Allocator, idx: usize) void {
    const file = self.file;
    const story = file.editor.ink_preview_story orelse return;
    story.chooseChoiceIndex(idx) catch |err| {
        if (file.editor.ink_preview_err) |m| gpa.free(m);
        file.editor.ink_preview_err = std.fmt.allocPrint(gpa, "choice failed: {s}", .{@errorName(err)}) catch return;
        return;
    };
    appendContOutput(gpa, file);
}

fn onContinue(self: *InkPreviewWidget, gpa: std.mem.Allocator) void {
    appendContOutput(gpa, self.file);
}

pub fn processEvents(self: *InkPreviewWidget) void {
    const file = self.file;
    const gpa = dvui_editor.app.gpa;
    const raw = file.content;
    const content: []const u8 = raw[0 .. std.mem.indexOfScalar(u8, raw, 0) orelse raw.len];

    var wh = std.hash.Wyhash.init(0);
    wh.update(content);
    const h = wh.final();

    if (file.editor.ink_preview_content_hash != h) {
        rebuildStory(self, gpa, content);
        file.editor.ink_preview_content_hash = h;
    }

    var scroll = dvui.scrollArea(@src(), .{
        .scroll_info = &file.editor.ink_preview_scroll,
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
        .id_extra = file.id,
    });
    defer scroll.deinit();

    var col = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .horizontal,
        .padding = .{ .x = 6, .y = 6, .w = 6, .h = 6 },
    });
    defer col.deinit();

    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer row.deinit();
        if (dvui.button(@src(), "Restart", .{}, .{ .id_extra = file.id ^ 0x494e4b52 })) {
            file.editor.ink_preview_content_hash = std.math.maxInt(u64);
        }
    }

    if (file.editor.ink_preview_err) |msg| {
        dvui.labelNoFmt(
            @src(),
            msg,
            .{},
            .{
                .expand = .horizontal,
                .color_text = dvui.themeGet().color(.err, .text).opacity(0.9),
                .id_extra = file.id ^ 0x454e4b45,
            },
        );
    }

    if (file.editor.ink_preview_transcript.items.len > 0) {
        dvui.labelNoFmt(
            @src(),
            file.editor.ink_preview_transcript.items,
            .{},
            .{ .expand = .horizontal, .id_extra = file.id ^ 0x5452414e },
        );
    }

    if (file.editor.ink_preview_done) {
        return;
    }

    const story = file.editor.ink_preview_story orelse {
        if (file.editor.ink_preview_err == null and content.len == 0) {
            dvui.labelNoFmt(@src(), "Empty document.", .{}, .{ .expand = .horizontal, .id_extra = file.id ^ 0x454d5054 });
        }
        return;
    };

    const choices = story.currentChoices();
    if (choices.len > 0) {
        // Snapshot labels before any button runs: chooseChoiceIndex + cont() frees the
        // runtime's choice list, so later `choice.text` slices would be dangling in the same loop.
        const aa = dvui_editor.editor.arena.allocator();
        const labels = aa.alloc([]const u8, choices.len) catch return;
        for (choices, 0..) |c, i| {
            labels[i] = if (c.text.len > 0)
                (aa.dupe(u8, c.text) catch return)
            else
                "(choice)";
        }
        for (labels, 0..) |label, i| {
            if (dvui.button(@src(), label, .{}, .{ .expand = .horizontal, .id_extra = file.id ^ 0x43484345 ^ @as(u64, @intCast(i)) })) {
                self.onChoice(gpa, i);
            }
        }
    } else if (story.canContinue()) {
        if (dvui.button(@src(), "Continue", .{}, .{ .expand = .horizontal, .id_extra = file.id ^ 0x434f4e54 })) {
            self.onContinue(gpa);
        }
    }
}
