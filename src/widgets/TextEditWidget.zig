//! Reusable multi-line text edit widget.
//!
//! Self-contained: only depends on `std` + `dvui`, so the same source
//! file can be consumed by dvui-editor itself and by other dvui apps
//! (e.g. graphl/ide) that want a code-editor-like text input. Tree-sitter
//! syntax highlighting is exposed verbatim through dvui's
//! `TextEntryWidget.InitOptions.tree_sitter`.
const std = @import("std");
const dvui = @import("dvui");

pub const TextEditWidget = @This();

pub const TreeSitter = if (dvui.useTreeSitter) struct {
    language: *dvui.c.TSLanguage,
    queries: []const u8,
    highlights: []const dvui.TextEntryWidget.SyntaxHighlight,
    /// If true, dvui dumps every capture to dvui.log.debug.
    log_captures: bool = false,
} else void;

pub const InitOptions = struct {
    /// Used by dvui to grow/shrink the backing buffer in response to edits.
    allocator: std.mem.Allocator,
    /// Backing storage for the edited text. The widget will realloc this
    /// slice as needed via `allocator`.
    backing: *[]u8,
    /// Faded text shown when the buffer is empty.
    placeholder: []const u8 = "",
    multiline: bool = true,
    cache_layout: bool = true,
    scroll_horizontal: bool = true,
    /// Disambiguator for cases where multiple TextEditWidgets share the same
    /// `@src()` site (e.g. one per open file).
    id_extra: usize = 0,
    /// Optional syntax highlighting. Pass null to disable.
    tree_sitter: ?TreeSitter = null,
};

opts: InitOptions,

pub fn init(src: std.builtin.SourceLocation, opts: InitOptions) TextEditWidget {
    _ = src;
    return .{ .opts = opts };
}

pub fn deinit(_: TextEditWidget) void {}

pub fn processEvents(self: *TextEditWidget) void {
    var entry_opts: dvui.TextEntryWidget.InitOptions = .{
        .placeholder = self.opts.placeholder,
        .multiline = self.opts.multiline,
        .cache_layout = self.opts.cache_layout,
        .scroll_horizontal = self.opts.scroll_horizontal,
        .text = .{
            .buffer_dynamic = .{
                .allocator = self.opts.allocator,
                .backing = self.opts.backing,
            },
        },
    };

    if (dvui.useTreeSitter) {
        if (self.opts.tree_sitter) |ts| {
            entry_opts.tree_sitter = .{
                .language = ts.language,
                .queries = ts.queries,
                .highlights = ts.highlights,
                .log_captures = ts.log_captures,
            };
        }
    }

    const text_edit = dvui.textEntry(@src(), entry_opts, .{
        .expand = .both,
        .id_extra = self.opts.id_extra,
    });
    defer text_edit.deinit();
}
