//! Transport-agnostic, bidirectional byte stream used to talk to a language
//! server. The LSP framing (Content-Length headers) and JSON-RPC live in
//! `Client`; a transport only moves raw bytes.
//!
//! Concrete transports are created by the backend (see `backend.startLspServer`):
//! a desktop backend backs this with a child process' stdin/stdout, while a web
//! backend would back it with a web worker `MessagePort`.

const Transport = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const Error = error{
    /// The peer went away or the underlying stream failed unrecoverably.
    Failed,
};

pub const VTable = struct {
    /// Block until at least one byte is available, then copy up to
    /// `buffer.len` bytes into `buffer`. Returns the number of bytes read, or
    /// `0` once the stream has been closed cleanly (EOF).
    read: *const fn (ptr: *anyopaque, buffer: []u8) Error!usize,

    /// Write all of `bytes` to the peer.
    write: *const fn (ptr: *anyopaque, bytes: []const u8) Error!void,

    /// Terminate the connection so any in-flight or future `read` returns `0`.
    /// Idempotent. Does not free the transport; call `destroy` for that, but
    /// only once no thread can call `read`/`write` anymore.
    close: *const fn (ptr: *anyopaque) void,

    /// Release all resources owned by the transport.
    destroy: *const fn (ptr: *anyopaque) void,
};

pub fn read(self: Transport, buffer: []u8) Error!usize {
    return self.vtable.read(self.ptr, buffer);
}

pub fn write(self: Transport, bytes: []const u8) Error!void {
    return self.vtable.write(self.ptr, bytes);
}

pub fn close(self: Transport) void {
    self.vtable.close(self.ptr);
}

pub fn destroy(self: Transport) void {
    self.vtable.destroy(self.ptr);
}
