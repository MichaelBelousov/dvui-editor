// These are functions specific to the backend, which is currently SDL3
const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
const sdl3 = @import("sdl-backend").c;

const dvui_editor = @import("root.zig");
const lsp = @import("lsp/lsp.zig");
const zwindow = @import("zwindow");

pub const TitleBarButton = zwindow.TitleBarButton;

// Returns which title bar button (if any) is at the given client-area coordinates. Windows only; other platforms return null.
pub fn getTitleBarButtonAt(win: *dvui.Window, client_x: i32, client_y: i32) ?TitleBarButton {
    if (builtin.os.tag != .windows) return null;
    const hwnd = getWin32Hwnd(win) orelse return null;
    return zwindow.titleBarButtonAt(hwnd, client_x, client_y);
}

// Performs the window button action (minimize, maximize/restore, close). Call from app when user clicks your title bar buttons. Windows only.
pub fn performWindowButton(win: *dvui.Window, button: TitleBarButton) void {
    if (builtin.os.tag != .windows) return;
    const hwnd = getWin32Hwnd(win) orelse return;
    zwindow.performTitleBarButton(hwnd, button);
}

// Title bar button width in pixels (same as hit-test area). Use for laying out three buttons on the right. Windows only; returns 0 on other platforms.
pub fn getTitleBarButtonWidth(win: *dvui.Window) i32 {
    _ = win;
    if (builtin.os.tag != .windows) return 0;
    return zwindow.titleBarButtonWidth();
}

fn getWin32Hwnd(win: *dvui.Window) ?*anyopaque {
    const raw = sdl3.SDL_GetPointerProperty(
        sdl3.SDL_GetWindowProperties(win.backend.impl.window),
        sdl3.SDL_PROP_WINDOW_WIN32_HWND_POINTER,
        null,
    );
    return if (raw != null) @ptrCast(raw) else null;
}

/// Native Win32 HWND for the DVUI SDL window (other platforms return null).
pub fn win32Hwnd(win: *dvui.Window) ?*anyopaque {
    return getWin32Hwnd(win);
}

pub fn isMaximized(win: *dvui.Window) bool {
    const flags = sdl3.SDL_GetWindowFlags(win.backend.impl.window);
    return flags & sdl3.SDL_WINDOW_FULLSCREEN != 0 or flags & sdl3.SDL_WINDOW_BORDERLESS != 0;
}

pub fn setWindowStyle(win: *dvui.Window) void {
    if (builtin.os.tag == .macos) {
        const raw_ptr = sdl3.SDL_GetPointerProperty(
            sdl3.SDL_GetWindowProperties(win.backend.impl.window),
            sdl3.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,
            null,
        );
        if (raw_ptr != null) {
            zwindow.applyTransparentTitlebar(@ptrCast(raw_ptr));
        }
    } else if (builtin.os.tag == .windows) {
        const hwnd = getWin32Hwnd(win) orelse return;
        zwindow.applyTransparentTitlebar(hwnd);
    }
}

pub fn setTitlebarColor(win: *dvui.Window, color: dvui.Color) void {
    const chrome = zwindow.FrameChrome{
        .r = @as(f64, @floatFromInt(color.r)) / 255.0,
        .g = @as(f64, @floatFromInt(color.g)) / 255.0,
        .b = @as(f64, @floatFromInt(color.b)) / 255.0,
        .a = @as(f64, @floatFromInt(color.a)) / 255.0,
        .dark = dvui.themeGet().dark,
        .policy = .full_vibrancy,
    };
    if (builtin.os.tag == .macos) {
        const raw_ptr = sdl3.SDL_GetPointerProperty(
            sdl3.SDL_GetWindowProperties(win.backend.impl.window),
            sdl3.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,
            null,
        );
        if (raw_ptr != null) zwindow.setFrameChrome(@ptrCast(raw_ptr), chrome);
    } else if (builtin.os.tag == .windows) {
        const hwnd = getWin32Hwnd(win) orelse return;
        zwindow.setFrameChrome(hwnd, chrome);
    }
}

pub fn showSimpleMessage(title: [:0]const u8, message: [:0]const u8) void {
    if (sdl3.SDL_ShowSimpleMessageBox(sdl3.SDL_MESSAGEBOX_INFORMATION, title, message, dvui.currentWindow().backend.impl.window)) {
        std.log.debug("true!", .{});
    }
}

pub fn showSaveFileDialog(cb: *const fn (?[][:0]const u8) void, filters: []const sdl3.SDL_DialogFileFilter, default_filename: []const u8, default_folder: ?[]const u8) void {
    const default: [:0]const u8 = blk: {
        if (default_folder) |folder| {
            break :blk std.fs.path.joinZ(dvui_editor.app.allocator, &.{ folder, default_filename }) catch "untitled";
        } else if (dvui_editor.editor.recents.last_save_folder) |last_save_folder| {
            break :blk std.fs.path.joinZ(dvui_editor.app.allocator, &.{ last_save_folder, default_filename }) catch "untitled";
        } else {
            break :blk std.fs.path.joinZ(dvui_editor.app.allocator, &.{ dvui_editor.editor.folder orelse "", default_filename }) catch "untitled";
        }
    };
    defer dvui_editor.app.allocator.free(default);
    sdl3.SDL_ShowSaveFileDialog(GenericSaveDialogCallback, @ptrCast(@alignCast(@constCast(cb))), dvui.currentWindow().backend.impl.window, filters.ptr, @intCast(filters.len), default);
}

pub fn showOpenFileDialog(cb: *const fn (?[][:0]const u8) void, filters: []const sdl3.SDL_DialogFileFilter, default_filename: []const u8, default_folder: ?[]const u8) void {
    const default: [:0]const u8 = blk: {
        if (default_folder) |folder| {
            break :blk std.fs.path.joinZ(dvui_editor.app.allocator, &.{ folder, default_filename }) catch "untitled";
        } else if (dvui_editor.editor.recents.last_open_folder) |last_open_folder| {
            break :blk std.fs.path.joinZ(dvui_editor.app.allocator, &.{ last_open_folder, default_filename }) catch "untitled";
        } else {
            break :blk std.fs.path.joinZ(dvui_editor.app.allocator, &.{ dvui_editor.editor.folder orelse "", default_filename }) catch "untitled";
        }
    };
    defer dvui_editor.app.allocator.free(default);
    sdl3.SDL_ShowOpenFileDialog(GenericOpenDialogCallback, @ptrCast(@alignCast(@constCast(cb))), dvui.currentWindow().backend.impl.window, filters.ptr, @intCast(filters.len), default.ptr, true);
}

pub fn showOpenFolderDialog(cb: *const fn (?[][:0]const u8) void, default_folder: ?[]const u8) void {
    const default: [:0]const u8 = blk: {
        if (default_folder) |folder| {
            break :blk std.fmt.allocPrintSentinel(dvui_editor.app.allocator, "{s}", .{folder}, 0) catch "untitled";
        } else {
            if (dvui_editor.editor.recents.last_open_folder) |last_open_folder| {
                break :blk std.fmt.allocPrintSentinel(dvui_editor.app.allocator, "{s}", .{last_open_folder}, 0) catch "untitled";
            } else {
                break :blk std.fmt.allocPrintSentinel(dvui_editor.app.allocator, "{s}", .{dvui_editor.editor.folder orelse ""}, 0) catch "untitled";
            }
        }
    };
    defer dvui_editor.app.allocator.free(default);
    sdl3.SDL_ShowOpenFolderDialog(GenericOpenDialogCallback, @ptrCast(@alignCast(@constCast(cb))), dvui.currentWindow().backend.impl.window, default.ptr, false);
}

pub const StartLspError = error{
    /// Spawning servers is not yet implemented on the web backend.
    WebWorkerNotImplemented,
} || std.process.SpawnError || std.mem.Allocator.Error;

/// Start a language server and return a transport-agnostic byte stream to it.
///
/// On desktop this resolves `argv[0]` against PATH (so `"zls"` finds a system
/// install) and spawns a child process, wiring its stdin/stdout as the
/// transport. On the web this would instead post a message to spawn a Web
/// Worker running the server and wrap its `MessagePort`; that path is not
/// implemented yet.
pub fn startLspServer(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) StartLspError!lsp.Transport {
    if (comptime builtin.target.cpu.arch.isWasm()) {
        return error.WebWorkerNotImplemented;
    }

    const self = try gpa.create(ProcessTransport);
    errdefer gpa.destroy(self);

    const child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .inherit,
    });

    self.* = .{ .gpa = gpa, .io = io, .child = child };
    return .{ .ptr = self, .vtable = &ProcessTransport.vtable };
}

/// A `lsp.Transport` backed by a child process' stdin/stdout pipes.
const ProcessTransport = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    child: std.process.Child,
    closed: bool = false,

    const vtable = lsp.Transport.VTable{
        .read = read,
        .write = write,
        .close = close,
        .destroy = destroy,
    };

    fn read(ptr: *anyopaque, buffer: []u8) lsp.Transport.Error!usize {
        const self: *ProcessTransport = @ptrCast(@alignCast(ptr));
        const stdout = self.child.stdout orelse return 0;
        return stdout.readStreaming(self.io, &[_][]u8{buffer}) catch |err| switch (err) {
            error.EndOfStream => 0,
            else => error.Failed,
        };
    }

    fn write(ptr: *anyopaque, bytes: []const u8) lsp.Transport.Error!void {
        const self: *ProcessTransport = @ptrCast(@alignCast(ptr));
        const stdin = self.child.stdin orelse return error.Failed;
        stdin.writeStreamingAll(self.io, bytes) catch return error.Failed;
    }

    fn close(ptr: *anyopaque) void {
        const self: *ProcessTransport = @ptrCast(@alignCast(ptr));
        if (self.closed) return;
        self.closed = true;
        // Close stdin so the server sees EOF, then kill to unblock any pending
        // read on stdout (the reader thread observes a clean EOF).
        if (self.child.stdin) |f| {
            f.close(self.io);
            self.child.stdin = null;
        }
        if (self.child.id != null) self.child.kill(self.io);
    }

    fn destroy(ptr: *anyopaque) void {
        const self: *ProcessTransport = @ptrCast(@alignCast(ptr));
        if (self.child.id != null) self.child.kill(self.io);
        if (self.child.stdin) |f| f.close(self.io);
        if (self.child.stdout) |f| f.close(self.io);
        if (self.child.stderr) |f| f.close(self.io);
        self.gpa.destroy(self);
    }
};

fn GenericSaveDialogCallback(cb: ?*anyopaque, files: [*c]const [*c]const u8, _: c_int) callconv(.c) void {
    GenericDialogCallback(cb, files, .save);
}

fn GenericOpenDialogCallback(cb: ?*anyopaque, files: [*c]const [*c]const u8, _: c_int) callconv(.c) void {
    GenericDialogCallback(cb, files, .open);
}

fn GenericDialogCallback(cb: ?*anyopaque, files: [*c]const [*c]const u8, mode: enum { save, open }) void {
    const callback: *const fn (?[][:0]const u8) void = @ptrCast(@alignCast(@constCast(cb)));

    // Try to count the number of files until we hit a null pointer.
    var path_count: usize = 0;
    while (files[path_count] != null) : (path_count += 1) {}

    const zig_files: [][:0]const u8 = blk: {
        var result: [100][:0]const u8 = undefined; // Arbitrary max; refine as needed
        var i: usize = 0;
        while (i < path_count) : (i += 1) {
            result[i] = std.mem.span(files[i]);
        }
        break :blk result[0..path_count];
    };

    if (zig_files.len == 0) {
        callback(null);
        return;
    }

    { // Save the open or save folder for the next time the dialog is shown
        if (std.fs.path.dirname(zig_files[0])) |dir| {
            if (mode == .save) {
                if (dvui_editor.editor.recents.last_save_folder) |last_save_folder| {
                    dvui_editor.app.allocator.free(last_save_folder);
                }
                dvui_editor.editor.recents.last_save_folder = dvui_editor.app.allocator.dupe(u8, dir) catch {
                    dvui.log.err("Failed to dupe directory {s}", .{dir});
                    return;
                };
            } else {
                if (dvui_editor.editor.recents.last_open_folder) |last_open_folder| {
                    dvui_editor.app.allocator.free(last_open_folder);
                }
                dvui_editor.editor.recents.last_open_folder = dvui_editor.app.allocator.dupe(u8, dir) catch {
                    dvui.log.err("Failed to dupe directory {s}", .{dir});
                    return;
                };
            }
        }
    }

    callback(zig_files);
}

const fake_lsp_server_py =
    \\import sys, json
    \\def read_msg():
    \\    headers = b""
    \\    while b"\r\n\r\n" not in headers:
    \\        ch = sys.stdin.buffer.read(1)
    \\        if not ch: return None
    \\        headers += ch
    \\    length = 0
    \\    for line in headers.split(b"\r\n"):
    \\        if line.lower().startswith(b"content-length:"):
    \\            length = int(line.split(b":")[1].strip())
    \\    return json.loads(sys.stdin.buffer.read(length))
    \\def send(obj):
    \\    data = json.dumps(obj).encode()
    \\    sys.stdout.buffer.write(b"Content-Length: %d\r\n\r\n" % len(data))
    \\    sys.stdout.buffer.write(data)
    \\    sys.stdout.buffer.flush()
    \\while True:
    \\    msg = read_msg()
    \\    if msg is None: break
    \\    m, mid = msg.get("method"), msg.get("id")
    \\    if m == "initialize":
    \\        send({"jsonrpc":"2.0","id":mid,"result":{"capabilities":{}}})
    \\    elif m == "textDocument/hover":
    \\        send({"jsonrpc":"2.0","id":mid,"result":{"contents":{"kind":"markdown","value":"HOVER_OK"}}})
    \\    elif m == "shutdown":
    \\        send({"jsonrpc":"2.0","id":mid,"result":None})
    \\    elif m == "exit":
    \\        break
    \\
;

fn waitForResponse(io: std.Io, client: *lsp.Client, id: i64) !std.json.Parsed(std.json.Value) {
    var attempts: usize = 0;
    while (attempts < 500) : (attempts += 1) { // ~5s budget
        if (client.takeResponse(id)) |resp| return resp;
        std.Io.sleep(io, std.Io.Duration.fromMilliseconds(10), .awake) catch {};
    }
    return error.Timeout;
}

test "lsp client drives a real server over a process transport" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const script_path = "/tmp/dvui_editor_fake_lsp_test.py";
    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = script_path,
        .data = fake_lsp_server_py,
        .flags = .{},
    }) catch return error.SkipZigTest;

    const transport = startLspServer(gpa, io, &.{ "python3", script_path }) catch return error.SkipZigTest;
    const client = try lsp.Client.create(gpa, io, transport, null);
    defer client.deinit();
    try client.start();

    const init_id = try client.initialize(null);
    {
        const resp = try waitForResponse(io, client, init_id);
        defer resp.deinit();
        try std.testing.expect(resp.value == .object);
        try std.testing.expect(resp.value.object.get("result") != null);
    }
    try client.initialized();

    const hover_id = try client.hover("file:///tmp/x.zig", .{ .line = 0, .character = 0 });
    {
        const resp = try waitForResponse(io, client, hover_id);
        defer resp.deinit();
        const text = lsp.Manager.extractHoverTextForTest(gpa, resp.value) orelse return error.NoHoverText;
        defer gpa.free(text);
        try std.testing.expectEqualStrings("HOVER_OK", text);
    }
}
