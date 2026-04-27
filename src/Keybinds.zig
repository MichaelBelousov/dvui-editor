const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");

const inkz_editor = @import("root.zig");

pub const Keybinds = @This();

pub fn register() !void {
    const window = dvui.currentWindow();

    if (builtin.os.tag.isDarwin()) {
        try window.keybinds.putNoClobber(window.gpa, "open_folder", .{ .key = .f, .command = true });
        try window.keybinds.putNoClobber(window.gpa, "open_files", .{ .key = .o, .command = true });
        try window.keybinds.putNoClobber(window.gpa, "undo", .{ .key = .z, .command = true, .shift = false });
        try window.keybinds.putNoClobber(window.gpa, "redo", .{ .key = .z, .command = true, .shift = true });
        try window.keybinds.putNoClobber(window.gpa, "zoom", .{ .command = true });
        try window.keybinds.putNoClobber(window.gpa, "save", .{ .command = true, .key = .s });
        try window.keybinds.putNoClobber(window.gpa, "sample", .{ .control = true });
        try window.keybinds.putNoClobber(window.gpa, "transform", .{ .command = true, .key = .t });
        try window.keybinds.putNoClobber(window.gpa, "explorer", .{ .command = true, .key = .e });
        try window.keybinds.putNoClobber(window.gpa, "workspace", .{ .command = true, .key = .w });
        try window.keybinds.putNoClobber(window.gpa, "export", .{ .command = true, .key = .p });
    } else {
        try window.keybinds.putNoClobber(window.gpa, "open_folder", .{ .key = .f, .control = true });
        try window.keybinds.putNoClobber(window.gpa, "open_files", .{ .key = .o, .control = true });
        try window.keybinds.putNoClobber(window.gpa, "undo", .{ .key = .z, .control = true, .shift = false });
        try window.keybinds.putNoClobber(window.gpa, "redo", .{ .key = .z, .control = true, .shift = true });
        try window.keybinds.putNoClobber(window.gpa, "zoom", .{ .control = true });
        try window.keybinds.putNoClobber(window.gpa, "save", .{ .control = true, .key = .s });
        try window.keybinds.putNoClobber(window.gpa, "sample", .{ .alt = true });
        try window.keybinds.putNoClobber(window.gpa, "transform", .{ .control = true, .key = .t });
        try window.keybinds.putNoClobber(window.gpa, "explorer", .{ .control = true, .key = .e });
        try window.keybinds.putNoClobber(window.gpa, "workspace", .{ .control = true, .key = .w });
        try window.keybinds.putNoClobber(window.gpa, "export", .{ .control = true, .key = .p });
    }

    try window.keybinds.putNoClobber(window.gpa, "shift", .{ .shift = true });
    try window.keybinds.putNoClobber(window.gpa, "increase_stroke_size", .{ .key = .right_bracket });
    try window.keybinds.putNoClobber(window.gpa, "decrease_stroke_size", .{ .key = .left_bracket });
    try window.keybinds.putNoClobber(window.gpa, "quick_tools", .{ .key = .space });

    try window.keybinds.putNoClobber(window.gpa, "pencil", .{ .key = .d, .command = false, .control = false, .alt = false, .shift = false });
    try window.keybinds.putNoClobber(window.gpa, "eraser", .{ .key = .e, .command = false, .control = false, .alt = false, .shift = false });
    try window.keybinds.putNoClobber(window.gpa, "bucket", .{ .key = .b, .command = false, .control = false, .alt = false, .shift = false });
    try window.keybinds.putNoClobber(window.gpa, "selection", .{ .key = .s, .command = false, .control = false, .alt = false, .shift = false });
    try window.keybinds.putNoClobber(window.gpa, "pointer", .{ .key = .escape });

    try window.keybinds.putNoClobber(window.gpa, "up", .{ .key = .up });
    try window.keybinds.putNoClobber(window.gpa, "down", .{ .key = .down });
    try window.keybinds.putNoClobber(window.gpa, "left", .{ .key = .left });
    try window.keybinds.putNoClobber(window.gpa, "right", .{ .key = .right });

    try window.keybinds.putNoClobber(window.gpa, "cancel", .{ .key = .escape });
}

// These keybinds are available regardless of the currently focused widget.
// Any binds that need to be consumed by a specific widget do not need to trigger here.
pub fn tick() !void {
    for (dvui.events()) |e| {
        if (e.handled) continue;

        switch (e.evt) {
            .key => |ke| {
                // macOS: NSMenu key equivalents already call `PixiNativeMenuAction` (see Editor.flushQueuedNativeMenuActions).
                // SDL still delivers the same key events, so handling them here too would run the action twice.
                if (builtin.os.tag != .macos) {
                    if (ke.matchBind("open_folder") and ke.action == .down) {
                        if (try dvui.dialogNativeFolderSelect(dvui.currentWindow().arena(), .{
                            .title = "Open Project Folder",
                        })) |folder| {
                            try inkz_editor.editor.setProjectFolder(folder);
                        }
                    }

                    if (ke.matchBind("open_files") and ke.action == .down) {
                        if (try dvui.dialogNativeFileOpenMultiple(
                            dvui.currentWindow().arena(),
                            .{ .title = "Open Files...", .filter_description = ".txt, .md", .filters = &.{ "*.txt", "*.md" } },
                        )) |files| {
                            for (files) |file| {
                                _ = inkz_editor.editor.openFilePath(file, inkz_editor.editor.open_workspace_grouping) catch {
                                    std.log.err("Failed to open file: {s}", .{file});
                                };
                            }
                        }
                    }
                }

                if (builtin.os.tag != .macos) {
                    if (ke.matchBind("explorer") and ke.action == .down) {
                        if (inkz_editor.editor.explorer.closed) {
                            inkz_editor.editor.explorer.open();
                        } else {
                            inkz_editor.editor.explorer.close();
                        }
                    }
                }

                // if (ke.matchBind("activate") and ke.action == .down) {
                //     inkz_editor.editor.accept() catch {
                //         std.log.err("Failed to accept", .{});
                //     };
                // }

                // if (ke.matchBind("cancel") and ke.action == .down) {
                //     inkz_editor.editor.cancel() catch {
                //         std.log.err("Failed to cancel", .{});
                //     };
                // }

                if (builtin.os.tag != .macos) {
                    if (ke.matchBind("undo") and (ke.action == .down or ke.action == .repeat)) {
                        inkz_editor.editor.undo() catch {
                            std.log.err("Failed to undo", .{});
                        };
                    }

                    if (ke.matchBind("copy") and ke.action == .down) {
                        inkz_editor.editor.copy() catch {
                            std.log.err("Failed to copy", .{});
                        };
                    }

                    if (ke.matchBind("paste") and ke.action == .down) {
                        inkz_editor.editor.paste() catch {
                            std.log.err("Failed to paste", .{});
                        };
                    }

                    if (ke.matchBind("redo") and (ke.action == .down or ke.action == .repeat)) {
                        inkz_editor.editor.redo() catch {
                            std.log.err("Failed to redo", .{});
                        };
                    }

                    if (ke.matchBind("save") and ke.action == .down) {
                        inkz_editor.editor.save() catch {
                            std.log.err("Failed to save", .{});
                        };
                    }

                    // if (ke.matchBind("transform") and ke.action == .down) {
                    //     inkz_editor.editor.transform() catch {
                    //         std.log.err("Failed to transform", .{});
                    //     };
                    // }
                }

                // if (ke.matchBind("pencil") and ke.action == .down) {
                //     inkz_editor.editor.tools.set(.pencil);
                // }
                // if (ke.matchBind("eraser") and ke.action == .down) {
                //     inkz_editor.editor.tools.set(.eraser);
                // }
                // if (ke.matchBind("bucket") and ke.action == .down) {
                //     inkz_editor.editor.tools.set(.bucket);
                // }
                // if (ke.matchBind("pointer") and ke.action == .down) {
                //     inkz_editor.editor.tools.set(.pointer);
                // }
                // if (ke.matchBind("selection") and ke.action == .down) {
                //     inkz_editor.editor.tools.set(.selection);
                // }
            },
            else => {},
        }
    }
}
