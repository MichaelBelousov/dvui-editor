const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

const dvui = @import("dvui");
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
const zmath = @import("zmath");

const dvui_editor = @import("root.zig");
const Editor = dvui_editor.Editor;

const icon = @embedFile("zig-favicon.png");
// const assets = @import("assets");

// const icon = assets.files.@"icon.png";

// const cozette_ttf = assets.files.fonts.@"CozetteVector.ttf";
// const cozette_bold_ttf = assets.files.fonts.@"CozetteVectorBold.ttf";

const App = @This();
// App fields
io: Io,
gpa: std.mem.Allocator = undefined,
environ: *std.process.Environ.Map,

//delta_time: f32 = 0.0,

root_path: [:0]const u8 = undefined,
should_close: bool = false,
window: *dvui.Window = undefined,

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{ .config = .{ .options = .{
    .size = .{ .w = 1200.0, .h = 800.0 },
    .min_size = .{ .w = 640.0, .h = 480.0 },
    .title = "DVUI Editor",
    .icon = icon,
    .transparent = if (builtin.os.tag == .macos or builtin.os.tag == .windows) true else false,
} }, .frameFn = AppFrame, .initFn = AppInit, .deinitFn = AppDeinit };

pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

// Runs before the first frame, after backend and dvui.Window.init()
pub fn AppInit(win: *dvui.Window) !void {
    const io = dvui.io;
    const gpa = win.gpa;
    const environ = dvui.App.main_init.?.environ_map;

    // Run from the directory where the executable is located so relative assets can be found.
    // var buffer: [1024]u8 = undefined;
    // TODO: Where to find this function?
    // const path = std.Io.Dir.selfExeDirPath(buffer[0..]) catch ".";
    // std.posix.chdir(path) catch {};
    const path = ".";

    dvui_editor.app = try gpa.create(App);
    dvui_editor.app.* = .{
        .io = io,
        .gpa = gpa,
        .environ = environ,
        .window = win,
        .root_path = gpa.dupeZ(u8, path) catch ".",
    };

    dvui_editor.editor = try gpa.create(Editor);
    dvui_editor.editor.* = Editor.init(io, dvui_editor.app) catch unreachable;

    if (dvui.App.main_init) |pin| {
        const args = try pin.minimal.args.toSlice(pin.arena.allocator());
        cli_folder: {
            if (args.len <= 1 or args[1].len == 0) break :cli_folder;
            const folder_arg = args[1];
            const dir_res = if (std.Io.Dir.path.isAbsolute(folder_arg))
                std.Io.Dir.openDirAbsolute(io, folder_arg, .{ .iterate = true })
            else
                std.Io.Dir.cwd().openDir(io, folder_arg, .{ .iterate = true });
            const dir = dir_res catch |err| {
                dvui.log.err("Open folder argument is not a readable directory ({s}): {s}", .{ folder_arg, @errorName(err) });
                break :cli_folder;
            };
            defer std.Io.Dir.close(dir, io);

            dvui_editor.editor.setProjectFolder(folder_arg) catch |err| {
                dvui.log.err("Failed to open project folder {s}: {s}", .{ folder_arg, @errorName(err) });
            };
        }
    }

    // dvui.addFont("CozetteVector", cozette_ttf, null) catch {};
    // dvui.addFont("CozetteVectorBold", cozette_bold_ttf, null) catch {};
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {
    dvui_editor.editor.deinit() catch unreachable;
}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return try dvui_editor.editor.tick();
}
