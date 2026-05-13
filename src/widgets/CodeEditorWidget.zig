const std = @import("std");

const dvui = @import("dvui");

const dvui_editor = @import("../root.zig");

pub const CodeEditorWidget = @This();

file: *dvui_editor.Internal.TextFile = undefined,

const supported_extensions = [_][]const u8{
    ".zig",
    ".zon",
    ".py",
    ".js",
    ".java",
    ".cpp",
    ".c",
    ".cs",
    ".html",
    ".css",
    ".php",
    ".ts",
    ".swift",
    ".kt",
    ".go",
    ".rs",
    ".rb",
    ".sql",
    ".sh",
    ".r",
    ".m",
    ".pl",
};

pub fn init(src: std.builtin.SourceLocation, file: *dvui_editor.Internal.TextFile) CodeEditorWidget {
    _ = src;
    return .{ .file = file };
}

pub fn deinit(_: CodeEditorWidget) void {}

pub fn supportsPath(path: []const u8) bool {
    return supportsExtension(std.fs.path.extension(path));
}

pub fn supportsExtension(extension: []const u8) bool {
    inline for (supported_extensions) |supported| {
        if (std.ascii.eqlIgnoreCase(extension, supported)) return true;
    }

    return false;
}

pub fn processEvents(self: *CodeEditorWidget) void {
    var init_opts: dvui.TextEntryWidget.InitOptions = .{
        .placeholder = "Code",
        .multiline = true,
        .cache_layout = true,
        .scroll_horizontal = true,
        .text = .{
            .buffer_dynamic = .{
                .allocator = dvui_editor.app.gpa,
                .backing = &self.file.content,
            },
        },
    };

    if (TreeSitter.optionForPath(self.file.path)) |tree_sitter| {
        init_opts.tree_sitter = tree_sitter;
    }

    const text_edit = dvui.textEntry(
        @src(),
        init_opts,
        .{
            .expand = .both,
            .id_extra = self.file.id,
        },
    );
    defer text_edit.deinit();
}

/// Grammars we ship highlight queries for (mirrors linked `tree_sitter_*` symbols).
const zig_tree_sitter_highlight_query =
    \\; Types
    \\(builtin_type) @type.builtin
    \\
    \\; Constants
    \\[
    \\  "null"
    \\  "unreachable"
    \\  "undefined"
    \\] @constant.builtin
    \\
    \\; Fields
    \\(field_initializer . (identifier) @variable.member)
    \\(field_expression member: (identifier) @variable.member)
    \\(container_field name: (identifier) @variable.member)
    \\
    \\; Functions
    \\(builtin_identifier) @function.builtin
    \\(call_expression function: (identifier) @function.call)
    \\(call_expression function: (field_expression member: (identifier) @function.call))
    \\(function_declaration name: (identifier) @function)
    \\
    \\; Keywords
    \\[
    \\  "asm"
    \\  "defer"
    \\  "errdefer"
    \\  "test"
    \\  "error"
    \\  "const"
    \\  "var"
    \\] @keyword
    \\
    \\[
    \\  "struct"
    \\  "union"
    \\  "enum"
    \\  "opaque"
    \\] @keyword.type
    \\
    \\[
    \\  "async"
    \\  "await"
    \\  "suspend"
    \\  "nosuspend"
    \\  "resume"
    \\] @keyword.coroutine
    \\
    \\"fn" @keyword.function
    \\
    \\[
    \\  "and"
    \\  "or"
    \\  "orelse"
    \\] @keyword.operator
    \\
    \\"return" @keyword.return
    \\
    \\[
    \\  "if"
    \\  "else"
    \\  "switch"
    \\] @keyword.conditional
    \\
    \\[
    \\  "for"
    \\  "while"
    \\  "break"
    \\  "continue"
    \\] @keyword.repeat
    \\
    \\[
    \\  "usingnamespace"
    \\  "export"
    \\] @keyword.import
    \\
    \\[
    \\  "try"
    \\  "catch"
    \\] @keyword.exception
    \\
    \\[
    \\  "volatile"
    \\  "allowzero"
    \\  "noalias"
    \\  "addrspace"
    \\  "align"
    \\  "callconv"
    \\  "linksection"
    \\  "pub"
    \\  "inline"
    \\  "noinline"
    \\  "extern"
    \\  "comptime"
    \\  "packed"
    \\  "threadlocal"
    \\] @keyword.modifier
    \\
    \\; Operators
    \\[
    \\  "="
    \\  "*="
    \\  "/="
    \\  "%="
    \\  "+="
    \\  "-="
    \\  "<<="
    \\  ">>="
    \\  "&="
    \\  "^="
    \\  "|="
    \\  "!"
    \\  "~"
    \\  "-"
    \\  "&"
    \\  "=="
    \\  "!="
    \\  ">"
    \\  ">="
    \\  "<="
    \\  "<"
    \\  "^"
    \\  "|"
    \\  "<<"
    \\  ">>"
    \\  "+"
    \\  "++"
    \\  "*"
    \\  "/"
    \\  "%"
    \\  ".*"
    \\  ".?"
    \\  "?"
    \\] @operator
    \\
    \\; Literals
    \\(character) @character
    \\(string) @string
    \\(multiline_string) @string
    \\(integer) @number
    \\(float) @number.float
    \\(boolean) @boolean
    \\(escape_sequence) @string.escape
    \\
    \\; Punctuation
    \\[
    \\  "["
    \\  "]"
    \\  "("
    \\  ")"
    \\  "{"
    \\  "}"
    \\] @punctuation.bracket
    \\
    \\[
    \\  ";"
    \\  "."
    \\  ","
    \\  ":"
    \\  "=>"
    \\  "->"
    \\] @punctuation.delimiter
    \\
    \\(comment) @comment
;

pub const TreeSitterLanguage = enum {
    zig,
};

pub const tree_sitter_highlight_queries: std.enums.EnumMap(TreeSitterLanguage, []const u8) = .initFullWith(.{
    .zig = zig_tree_sitter_highlight_query,
});

const TreeSitter = if (dvui.useTreeSitter) struct {
    // DVUI currently links the Zig grammar; other CodeEditor extensions fall back to plain text.
    extern fn tree_sitter_zig() *dvui.c.TSLanguage;

    const highlights = [_]dvui.TextEntryWidget.SyntaxHighlight{
        highlight("keyword", .{ .r = 0xc6, .g = 0x78, .b = 0xdd }),
        highlight("operator", .{ .r = 0x89, .g = 0xdd, .b = 0xff }),
        highlight("punctuation", .{ .r = 0x8a, .g = 0x8f, .b = 0x98 }),
        highlight("type", .{ .r = 0xe5, .g = 0xc0, .b = 0x7b }),
        highlight("constant", .{ .r = 0xd1, .g = 0x9a, .b = 0x66 }),
        highlight("variable.member", .{ .r = 0x7e, .g = 0xc7, .b = 0xc7 }),
        highlight("function", .{ .r = 0x61, .g = 0xaf, .b = 0xef }),
        highlight("function.builtin", .{ .r = 0x56, .g = 0xb6, .b = 0xc2 }),
        highlight("string", .{ .r = 0x98, .g = 0xc3, .b = 0x79 }),
        highlight("character", .{ .r = 0x98, .g = 0xc3, .b = 0x79 }),
        highlight("number", .{ .r = 0xd1, .g = 0x9a, .b = 0x66 }),
        highlight("boolean", .{ .r = 0xd1, .g = 0x9a, .b = 0x66 }),
        highlight("comment", .{ .r = 0x7f, .g = 0x84, .b = 0x8e, .a = 0xcc }),
    };

    fn optionForPath(path: []const u8) ?dvui.TextEntryWidget.InitOptions.TreeSitterOption {
        return optionForExtension(std.fs.path.extension(path));
    }

    fn optionForExtension(extension: []const u8) ?dvui.TextEntryWidget.InitOptions.TreeSitterOption {
        if (std.ascii.eqlIgnoreCase(extension, ".zig")) return option(.zig, tree_sitter_zig());
        if (std.ascii.eqlIgnoreCase(extension, ".zon")) return option(.zig, tree_sitter_zig());

        return null;
    }

    fn option(lang: TreeSitterLanguage, language: *dvui.c.TSLanguage) dvui.TextEntryWidget.InitOptions.TreeSitterOption {
        return .{
            .language = language,
            .queries = tree_sitter_highlight_queries.getAssertContains(lang),
            .highlights = &highlights,
        };
    }

    fn highlight(name: []const u8, color: dvui.Color) dvui.TextEntryWidget.SyntaxHighlight {
        return .{
            .name = name,
            .opts = .{ .color_text = color },
        };
    }
} else struct {
    fn optionForPath(path: []const u8) ?dvui.TextEntryWidget.InitOptions.TreeSitterOption {
        _ = path;
        return null;
    }
};

test "zig tree-sitter highlight query compiles" {
    if (dvui.useTreeSitter) {
        const query_src = tree_sitter_highlight_queries.getAssertContains(.zig);
        var error_offset: u32 = undefined;
        var error_type: dvui.c.TSQueryError = undefined;
        const query = dvui.c.ts_query_new(
            TreeSitter.tree_sitter_zig(),
            query_src.ptr,
            @intCast(query_src.len),
            &error_offset,
            &error_type,
        ) orelse return error.InvalidTreeSitterQuery;
        defer dvui.c.ts_query_delete(query);
    }
}
