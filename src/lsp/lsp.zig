//! Transport-agnostic Language Server Protocol adapter.
//!
//! - `Transport` is a raw bidirectional byte stream, created by the backend.
//! - `Client` speaks JSON-RPC/LSP over a `Transport` with a background reader.
//! - `Manager` owns running servers per language and drives their lifecycle,
//!   exposing high-level operations like hover for the editor to call.

const std = @import("std");

pub const Transport = @import("Transport.zig");
pub const Client = @import("Client.zig");
pub const Manager = @import("Manager.zig");

/// Build a `file://` URI for an absolute filesystem path. Caller owns the
/// returned memory. This is a pragmatic encoder (it does not percent-encode
/// every reserved character) sufficient for local paths.
pub fn fileUriAlloc(gpa: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]u8 {
    if (@import("builtin").os.tag == .windows) {
        // file:///C:/foo with backslashes converted to forward slashes.
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(gpa);
        try buf.appendSlice(gpa, "file:///");
        for (path) |c| try buf.append(gpa, if (c == '\\') '/' else c);
        return buf.toOwnedSlice(gpa);
    }
    return std.fmt.allocPrint(gpa, "file://{s}", .{path});
}

test "fileUriAlloc posix" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const uri = try fileUriAlloc(std.testing.allocator, "/home/u/main.zig");
    defer std.testing.allocator.free(uri);
    try std.testing.expectEqualStrings("file:///home/u/main.zig", uri);
}
