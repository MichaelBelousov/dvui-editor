//! Owns the set of running language servers and drives their lifecycle. The
//! editor holds one `Manager`; it starts servers lazily per language, performs
//! the `initialize`/`initialized` handshake, keeps documents open, and turns
//! the asynchronous LSP request/response dance into simple per-frame polling
//! (e.g. `requestHover` + `takeHoverResult`).

const std = @import("std");
const Allocator = std.mem.Allocator;

const dvui = @import("dvui");

const dvui_editor = @import("../root.zig");
const lsp = @import("lsp.zig");
const Client = lsp.Client;

const Manager = @This();

gpa: Allocator,
window: ?*dvui.Window,
/// `file://` URI of the project root, used in `initialize`. Owned.
root_uri: ?[]u8 = null,

/// Keyed by language id (e.g. "zig"). Keys and values are owned.
servers: std.StringHashMapUnmanaged(*Server) = .empty,
/// Languages whose server failed to start; we won't keep retrying. Keys owned.
failed: std.StringHashMapUnmanaged(void) = .empty,

hover: HoverState = .{},

const ServerSpec = struct {
    language_id: []const u8,
    /// argv[0] is resolved against PATH by the backend.
    argv: []const []const u8,
};

/// Maps a language id to the server that handles it. Extend as needed.
fn specForLanguage(language_id: []const u8) ?ServerSpec {
    if (std.mem.eql(u8, language_id, "zig")) {
        return .{ .language_id = "zig", .argv = &.{"zls"} };
    }
    return null;
}

/// Maps a file extension to a language id, or null if unsupported.
pub fn languageForPath(path: []const u8) ?[]const u8 {
    const ext = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(ext, ".zig")) return "zig";
    if (std.ascii.eqlIgnoreCase(ext, ".zon")) return "zig";
    return null;
}

const Server = struct {
    client: *Client,
    state: enum { initializing, ready, failed } = .initializing,
    init_id: i64,
    /// Open documents, uri -> last sync version. Keys owned.
    opened: std.StringHashMapUnmanaged(i64) = .empty,

    fn deinit(self: *Server, gpa: Allocator) void {
        var it = self.opened.keyIterator();
        while (it.next()) |k| gpa.free(k.*);
        self.opened.deinit(gpa);
        self.client.deinit();
    }
};

const HoverState = struct {
    /// Borrowed key into `servers` of the client a hover was sent to.
    server_lang: ?[]const u8 = null,
    pending_id: ?i64 = null,
    /// Latest hover text, owned. Valid until the next `requestHover`.
    result: ?[]u8 = null,
};

pub fn init(gpa: Allocator, window: ?*dvui.Window) Manager {
    return .{ .gpa = gpa, .window = window };
}

pub fn deinit(self: *Manager) void {
    var it = self.servers.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit(self.gpa);
        self.gpa.destroy(entry.value_ptr.*);
        self.gpa.free(entry.key_ptr.*);
    }
    self.servers.deinit(self.gpa);
    var fit = self.failed.keyIterator();
    while (fit.next()) |k| self.gpa.free(k.*);
    self.failed.deinit(self.gpa);
    if (self.root_uri) |u| self.gpa.free(u);
    if (self.hover.result) |r| self.gpa.free(r);
}

/// Set the project root used for future `initialize` calls. Replaces any
/// previous value; already-running servers keep their original root.
pub fn setRootPath(self: *Manager, path: ?[]const u8) void {
    if (self.root_uri) |u| self.gpa.free(u);
    self.root_uri = null;
    if (path) |p| {
        self.root_uri = lsp.fileUriAlloc(self.gpa, p) catch null;
    }
}

fn ensureServer(self: *Manager, language_id: []const u8) !*Server {
    if (self.servers.get(language_id)) |s| return s;
    if (self.failed.contains(language_id)) return error.ServerStartFailed;

    return self.startServer(language_id) catch |err| {
        // Remember the failure so we don't try to spawn on every keystroke.
        const key = self.gpa.dupe(u8, language_id) catch return err;
        self.failed.put(self.gpa, key, {}) catch self.gpa.free(key);
        return err;
    };
}

fn startServer(self: *Manager, language_id: []const u8) !*Server {
    const spec = specForLanguage(language_id) orelse return error.UnsupportedLanguage;

    const io = dvui_editor.app.io;
    const transport = try dvui_editor.backend.startLspServer(self.gpa, io, spec.argv);
    errdefer transport.destroy();

    const client = try Client.create(self.gpa, io, transport, self.window);
    errdefer client.deinit();
    try client.start();

    const init_id = try client.initialize(self.root_uri);

    const server = try self.gpa.create(Server);
    errdefer self.gpa.destroy(server);
    server.* = .{ .client = client, .init_id = init_id };

    const key = try self.gpa.dupe(u8, language_id);
    errdefer self.gpa.free(key);
    try self.servers.put(self.gpa, key, server);

    dvui.log.info("LSP: started server for '{s}' ({s})", .{ language_id, spec.argv[0] });
    return server;
}

/// Advance server lifecycles and collect any hover reply. Call once per frame.
pub fn tick(self: *Manager) void {
    var it = self.servers.valueIterator();
    while (it.next()) |sp| {
        const server = sp.*;
        if (server.state == .initializing) {
            if (server.client.takeResponse(server.init_id)) |resp| {
                defer resp.deinit();
                if (responseIsError(resp.value)) {
                    server.state = .failed;
                    dvui.log.err("LSP: initialize failed", .{});
                } else {
                    server.client.initialized() catch {};
                    server.state = .ready;
                    dvui.log.info("LSP: server ready", .{});
                }
            }
        }
        // Drain server-initiated notifications we don't act on, so the queue
        // doesn't grow unbounded.
        while (server.client.pollNotification()) |n| n.deinit();
    }

    self.collectHover();
}

fn collectHover(self: *Manager) void {
    const lang = self.hover.server_lang orelse return;
    const id = self.hover.pending_id orelse return;
    const server = self.servers.get(lang) orelse return;

    if (server.client.takeResponse(id)) |resp| {
        defer resp.deinit();
        self.hover.pending_id = null;
        if (extractHoverText(self.gpa, resp.value)) |text| {
            if (self.hover.result) |old| self.gpa.free(old);
            self.hover.result = text;
        }
    }
}

/// Request hover info for `path` at `pos`. `text` is the current buffer
/// contents (used to keep the server in sync). No-op (returns false) if the
/// language is unsupported or the server isn't ready yet.
pub fn requestHover(self: *Manager, path: []const u8, text: []const u8, pos: Client.Position) bool {
    const language_id = languageForPath(path) orelse return false;
    const server = self.ensureServer(language_id) catch |err| {
        // `ServerStartFailed` is the cached-failure path; the real error was
        // already logged on the first attempt.
        if (err != error.ServerStartFailed)
            dvui.log.err("LSP: could not start server for '{s}': {s}", .{ language_id, @errorName(err) });
        return false;
    };
    if (server.state != .ready) return false;

    const uri = lsp.fileUriAlloc(self.gpa, path) catch return false;
    defer self.gpa.free(uri);

    self.syncDocument(server, uri, language_id, text) catch return false;

    const id = server.client.hover(uri, pos) catch return false;

    // Reset the previous result so stale text doesn't linger.
    if (self.hover.result) |old| self.gpa.free(old);
    self.hover.result = null;
    self.hover.pending_id = id;
    self.hover.server_lang = server_key: {
        // Use the stable key stored in the map.
        var it = self.servers.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* == server) break :server_key e.key_ptr.*;
        }
        break :server_key null;
    };
    return true;
}

/// Returns the most recent hover text, if any. Borrowed; valid until the next
/// `requestHover`.
pub fn takeHoverResult(self: *Manager) ?[]const u8 {
    return self.hover.result;
}

fn syncDocument(self: *Manager, server: *Server, uri: []const u8, language_id: []const u8, text: []const u8) !void {
    const gop = try server.opened.getOrPut(self.gpa, uri);
    if (!gop.found_existing) {
        gop.key_ptr.* = try self.gpa.dupe(u8, uri);
        gop.value_ptr.* = 1;
        try server.client.didOpen(uri, language_id, 1, text);
    } else {
        gop.value_ptr.* += 1;
        try server.client.didChangeFull(uri, gop.value_ptr.*, text);
    }
}

fn responseIsError(value: std.json.Value) bool {
    return switch (value) {
        .object => |o| o.get("error") != null,
        else => false,
    };
}

/// Extract human-readable text from a `textDocument/hover` result. Handles
/// `MarkupContent`, `MarkedString`, and arrays of those. Returns owned memory,
/// or null if there is no hover content.
fn extractHoverText(gpa: Allocator, response: std.json.Value) ?[]u8 {
    const obj = switch (response) {
        .object => |o| o,
        else => return null,
    };
    const result = obj.get("result") orelse return null;
    const result_obj = switch (result) {
        .object => |o| o,
        else => return null, // null result == no hover info
    };
    const contents = result_obj.get("contents") orelse return null;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(gpa);
    appendMarkedString(gpa, &buf, contents) catch return null;
    if (buf.items.len == 0) return null;
    return buf.toOwnedSlice(gpa) catch null;
}

fn appendMarkedString(gpa: Allocator, buf: *std.ArrayListUnmanaged(u8), value: std.json.Value) !void {
    switch (value) {
        .string => |s| try buf.appendSlice(gpa, s),
        .object => |o| {
            // MarkupContent { kind, value } or MarkedString { language, value }.
            if (o.get("value")) |v| {
                if (v == .string) try buf.appendSlice(gpa, v.string);
            }
        },
        .array => |arr| {
            for (arr.items, 0..) |item, i| {
                if (i != 0) try buf.appendSlice(gpa, "\n\n");
                try appendMarkedString(gpa, buf, item);
            }
        },
        else => {},
    }
}
