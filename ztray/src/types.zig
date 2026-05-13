const std = @import("std");

pub const ActionId = c_int;

pub const Modifier = enum(u8) {
    command,
    shift,
    option,
    control,
};

pub const Shortcut = struct {
    key: []const u8,
    modifiers: []const Modifier = &.{},
};

pub const Item = union(enum) {
    action: ActionItem,
    separator,

    pub const ActionItem = struct {
        title: []const u8,
        action_id: ActionId,
        shortcut: ?Shortcut = null,
        /// If non-null, shown in the Windows menu shortcut column instead of the default formatter.
        shortcut_display: ?[]const u8 = null,
        enabled: bool = true,
        /// macOS: when true, the next window close is suppressed (e.g. Cmd+W closes a tab instead of the window).
        suppress_next_window_close: bool = false,
    };
};

pub const Menu = struct {
    title: []const u8,
    items: []const Item,
};

pub const MenuBar = struct {
    menus: []const Menu,
};

pub fn modifierMask(shortcut: Shortcut) u32 {
    var mask: u32 = 0;
    for (shortcut.modifiers) |modifier| {
        mask |= switch (modifier) {
            .command => 1 << 0,
            .shift => 1 << 1,
            .option => 1 << 2,
            .control => 1 << 3,
        };
    }
    return mask;
}

/// Builds a Windows-style shortcut label (Ctrl+/Alt+/Shift+ + key). Treats `.command` like primary Ctrl for cross-platform menus.
pub fn formatWindowsShortcut(allocator: std.mem.Allocator, shortcut: Shortcut) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    const has_cmd = hasModifier(shortcut, .command);
    const has_ctrl = hasModifier(shortcut, .control);
    if (has_cmd or has_ctrl) try out.appendSlice(allocator, "Ctrl+");
    if (hasModifier(shortcut, .option)) try out.appendSlice(allocator, "Alt+");
    if (hasModifier(shortcut, .shift)) try out.appendSlice(allocator, "Shift+");

    for (shortcut.key) |c| {
        try out.append(allocator, if (c < 128) std.ascii.toUpper(c) else c);
    }
    return try out.toOwnedSlice(allocator);
}

fn hasModifier(shortcut: Shortcut, modifier: Modifier) bool {
    for (shortcut.modifiers) |existing| {
        if (existing == modifier) return true;
    }
    return false;
}

test "modifierMask empty" {
    const sc: Shortcut = .{ .key = "s", .modifiers = &.{} };
    try std.testing.expectEqual(@as(u32, 0), modifierMask(sc));
}

test "modifierMask command and shift" {
    const sc: Shortcut = .{ .key = "z", .modifiers = &.{ .command, .shift } };
    const m = modifierMask(sc);
    try std.testing.expectEqual(@as(u32, (1 << 0) | (1 << 1)), m);
}

test "formatWindowsShortcut command maps to Ctrl" {
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = "n", .modifiers = &.{.command} };
    const s = try formatWindowsShortcut(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Ctrl+N", s);
}

test "formatWindowsShortcut modifiers order" {
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = "x", .modifiers = &.{ .control, .option, .shift } };
    const s = try formatWindowsShortcut(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Ctrl+Alt+Shift+X", s);
}
