//! A minimal JSON-RPC 2.0 client speaking the Language Server Protocol over a
//! `Transport`. It is transport-agnostic: framing (Content-Length headers) and
//! message routing live here, while the actual byte stream is provided by the
//! backend (child process on desktop, web worker on web).
//!
//! A background thread reads framed messages from the transport and routes
//! them: responses are stored by request id, server-initiated notifications and
//! requests are queued. The GUI thread drains both each frame via
//! `takeResponse` / `pollNotification`, so nothing here blocks rendering.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dvui = @import("dvui");

const Transport = @import("Transport.zig");

const Client = @This();

gpa: Allocator,
/// Needed by `std.Io.Mutex` for blocking lock/unlock.
io: std.Io,
transport: Transport,
/// When set, a frame is requested on this window whenever a message arrives so
/// the GUI thread wakes up to drain it. Safe to call across threads.
window: ?*dvui.Window,

thread: ?std.Thread = null,
running: std.atomic.Value(bool) = .init(false),
next_id: std.atomic.Value(i64) = .init(1),

/// Guards `responses` and `notifications`.
mutex: std.Io.Mutex = .init,
/// Serializes writes to the transport.
write_mutex: std.Io.Mutex = .init,

/// Completed responses to our requests, keyed by request id. The GUI thread
/// removes and owns each one via `takeResponse`.
responses: std.AutoHashMapUnmanaged(i64, std.json.Parsed(std.json.Value)) = .empty,
/// FIFO of server-initiated notifications and requests, drained via
/// `pollNotification`.
notifications: std.ArrayListUnmanaged(std.json.Parsed(std.json.Value)) = .empty,

pub const Error = error{
    WriteFailed,
    OutOfMemory,
};

pub fn create(gpa: Allocator, io: std.Io, transport: Transport, window: ?*dvui.Window) Allocator.Error!*Client {
    const self = try gpa.create(Client);
    self.* = .{
        .gpa = gpa,
        .io = io,
        .transport = transport,
        .window = window,
    };
    return self;
}

/// Spawn the reader thread. Call once after `create`.
pub fn start(self: *Client) std.Thread.SpawnError!void {
    self.running.store(true, .release);
    self.thread = try std.Thread.spawn(.{}, readLoop, .{self});
}

pub fn deinit(self: *Client) void {
    self.running.store(false, .release);
    // Closing the transport unblocks the reader thread's pending read.
    self.transport.close();
    if (self.thread) |t| t.join();
    self.transport.destroy();

    self.mutex.lockUncancelable(self.io);
    var it = self.responses.valueIterator();
    while (it.next()) |p| p.deinit();
    self.responses.deinit(self.gpa);
    for (self.notifications.items) |p| p.deinit();
    self.notifications.deinit(self.gpa);
    self.mutex.unlock(self.io);

    self.gpa.destroy(self);
}

// --- Outgoing messages -----------------------------------------------------

fn nextId(self: *Client) i64 {
    return self.next_id.fetchAdd(1, .monotonic);
}

/// Send a request and return its id. Poll for the reply with `takeResponse`.
pub fn sendRequest(self: *Client, method: []const u8, params: anytype) Error!i64 {
    const id = self.nextId();
    const Msg = struct {
        jsonrpc: []const u8 = "2.0",
        id: i64,
        method: []const u8,
        params: @TypeOf(params),
    };
    try self.sendMessage(Msg{ .id = id, .method = method, .params = params });
    return id;
}

pub fn sendNotification(self: *Client, method: []const u8, params: anytype) Error!void {
    const Msg = struct {
        jsonrpc: []const u8 = "2.0",
        method: []const u8,
        params: @TypeOf(params),
    };
    try self.sendMessage(Msg{ .method = method, .params = params });
}

fn sendMessage(self: *Client, value: anytype) Error!void {
    const body = try std.json.Stringify.valueAlloc(self.gpa, value, .{});
    defer self.gpa.free(body);
    try self.sendFramed(body);
}

fn sendFramed(self: *Client, body: []const u8) Error!void {
    var hdr_buf: [64]u8 = undefined;
    const hdr = std.fmt.bufPrint(&hdr_buf, "Content-Length: {d}\r\n\r\n", .{body.len}) catch unreachable;

    self.write_mutex.lockUncancelable(self.io);
    defer self.write_mutex.unlock(self.io);
    self.transport.write(hdr) catch return error.WriteFailed;
    self.transport.write(body) catch return error.WriteFailed;
}

// --- LSP method helpers ----------------------------------------------------

pub const Position = struct { line: u32, character: u32 };

/// `initialize` handshake. Returns the request id; the server is not usable
/// until its reply arrives and `initialized` is sent.
pub fn initialize(self: *Client, root_uri: ?[]const u8) Error!i64 {
    return self.sendRequest("initialize", .{
        .processId = @as(?i64, null),
        .clientInfo = .{ .name = "dvui-editor", .version = "0.0.0" },
        .rootUri = root_uri,
        .capabilities = .{
            .textDocument = .{
                .hover = .{
                    .contentFormat = &[_][]const u8{ "markdown", "plaintext" },
                },
                .synchronization = .{
                    .didSave = false,
                    .dynamicRegistration = false,
                },
            },
        },
    });
}

pub fn initialized(self: *Client) Error!void {
    return self.sendNotification("initialized", .{});
}

pub fn didOpen(self: *Client, uri: []const u8, language_id: []const u8, version: i64, text: []const u8) Error!void {
    return self.sendNotification("textDocument/didOpen", .{
        .textDocument = .{
            .uri = uri,
            .languageId = language_id,
            .version = version,
            .text = text,
        },
    });
}

/// Full-document sync: replace the whole buffer contents.
pub fn didChangeFull(self: *Client, uri: []const u8, version: i64, text: []const u8) Error!void {
    return self.sendNotification("textDocument/didChange", .{
        .textDocument = .{ .uri = uri, .version = version },
        .contentChanges = .{.{ .text = text }},
    });
}

pub fn didClose(self: *Client, uri: []const u8) Error!void {
    return self.sendNotification("textDocument/didClose", .{
        .textDocument = .{ .uri = uri },
    });
}

/// Request hover info at a position. Returns the request id.
pub fn hover(self: *Client, uri: []const u8, pos: Position) Error!i64 {
    return self.sendRequest("textDocument/hover", .{
        .textDocument = .{ .uri = uri },
        .position = .{ .line = pos.line, .character = pos.character },
    });
}

pub fn shutdown(self: *Client) Error!i64 {
    return self.sendRequest("shutdown", .{});
}

// --- Incoming messages (polled by the GUI thread) --------------------------

/// Remove and return the response for `id`, if it has arrived. Caller owns the
/// result and must `deinit` it.
pub fn takeResponse(self: *Client, id: i64) ?std.json.Parsed(std.json.Value) {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (self.responses.fetchRemove(id)) |kv| return kv.value;
    return null;
}

/// Remove and return the oldest queued notification/server request. Caller owns
/// the result and must `deinit` it.
pub fn pollNotification(self: *Client) ?std.json.Parsed(std.json.Value) {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (self.notifications.items.len == 0) return null;
    return self.notifications.orderedRemove(0);
}

// --- Reader thread ---------------------------------------------------------

fn wake(self: *Client) void {
    if (self.window) |w| dvui.refresh(w, @src(), null);
}

fn readLoop(self: *Client) void {
    var fr: FrameReader = .{ .transport = self.transport, .gpa = self.gpa };
    defer fr.deinit();

    while (self.running.load(.acquire)) {
        const body = (fr.next() catch break) orelse break; // error or EOF
        self.handleMessage(body);
    }
}

fn handleMessage(self: *Client, body: []const u8) void {
    const parsed = std.json.parseFromSlice(std.json.Value, self.gpa, body, .{}) catch return;
    var keep = false;
    defer if (!keep) parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return,
    };

    const id_val = obj.get("id");
    if (obj.get("method") != null) {
        // Server-initiated: notification (no id) or request (with id).
        if (id_val) |idv| self.replyNull(idv) catch {};
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.notifications.append(self.gpa, parsed) catch return;
        keep = true;
    } else if (id_val) |idv| {
        // Response to one of our requests. We only issue integer ids.
        const id = switch (idv) {
            .integer => |i| i,
            else => return,
        };
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const gop = self.responses.getOrPut(self.gpa, id) catch return;
        if (gop.found_existing) gop.value_ptr.deinit();
        gop.value_ptr.* = parsed;
        keep = true;
    } else return;

    self.wake();
}

/// Acknowledge a server request we don't handle with a null result so the
/// server doesn't stall waiting on us (e.g. `window/workDoneProgress/create`).
fn replyNull(self: *Client, id: std.json.Value) Error!void {
    const Reply = struct {
        jsonrpc: []const u8 = "2.0",
        id: std.json.Value,
        result: ?u0 = null,
    };
    try self.sendMessage(Reply{ .id = id });
}

/// Reassembles Content-Length framed messages from a byte stream.
const FrameReader = struct {
    transport: Transport,
    gpa: Allocator,
    buf: std.ArrayListUnmanaged(u8) = .empty,
    /// Index of the first unconsumed byte in `buf`.
    start: usize = 0,

    fn deinit(self: *FrameReader) void {
        self.buf.deinit(self.gpa);
    }

    /// Returns the next complete message body, or null on EOF. The slice is
    /// valid only until the next call.
    fn next(self: *FrameReader) !?[]const u8 {
        // Drop consumed bytes so the buffer doesn't grow without bound.
        if (self.start > 0) {
            const remaining = self.buf.items[self.start..];
            std.mem.copyForwards(u8, self.buf.items[0..remaining.len], remaining);
            self.buf.items.len = remaining.len;
            self.start = 0;
        }

        while (true) {
            if (try self.tryParse()) |body| return body;

            try self.buf.ensureUnusedCapacity(self.gpa, 4096);
            const dst = self.buf.unusedCapacitySlice();
            const n = self.transport.read(dst) catch return error.ReadFailed;
            if (n == 0) return null; // clean EOF
            self.buf.items.len += n;
        }
    }

    fn tryParse(self: *FrameReader) !?[]const u8 {
        const data = self.buf.items[self.start..];
        const sep = std.mem.indexOf(u8, data, "\r\n\r\n") orelse return null;

        var content_len: ?usize = null;
        var lines = std.mem.splitSequence(u8, data[0..sep], "\r\n");
        while (lines.next()) |line| {
            const prefix = "content-length:";
            if (line.len >= prefix.len and std.ascii.eqlIgnoreCase(line[0..prefix.len], prefix)) {
                const v = std.mem.trim(u8, line[prefix.len..], " \t");
                content_len = std.fmt.parseInt(usize, v, 10) catch return error.BadFrame;
            }
        }
        const len = content_len orelse return error.BadFrame;

        const body_start = self.start + sep + 4;
        if (self.buf.items.len < body_start + len) return null; // need more bytes
        self.start = body_start + len;
        return self.buf.items[body_start .. body_start + len];
    }
};
