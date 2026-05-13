const std = @import("std");
const builtin = @import("builtin");

pub const ActionId = c_int;

/// Menu shortcut modifier keys (bitmask via [`modifierMask`]).
pub const Modifier = enum(u8) {
    /// Primary menu accelerator: ⌘ on macOS native menus; Ctrl on Windows/Linux. DVUI keybinds: Command on macOS, Control elsewhere (same as typical “File → New” chords).
    primary,
    /// OS super / meta / Windows (⊞) key. DVUI maps this to the GUI modifier on all platforms (see DVUI SDL `KMOD_LGUI` → `Mod.lcommand`). Native macOS menus map this to Command as well (no separate ⊞ in AppKit).
    super,
    shift,
    /// Alt on Windows/Linux; Option on macOS.
    alt,
    ctrl,
};

/// Key for a menu shortcut (letters and digits). Matches keys supported for DVUI keybind registration.
pub const ShortcutKey = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,

    /// Lowercase letter or digit for AppKit `keyEquivalent` / C string.
    pub fn keyEquivalentByte(self: ShortcutKey) u8 {
        return switch (self) {
            .a => 'a',
            .b => 'b',
            .c => 'c',
            .d => 'd',
            .e => 'e',
            .f => 'f',
            .g => 'g',
            .h => 'h',
            .i => 'i',
            .j => 'j',
            .k => 'k',
            .l => 'l',
            .m => 'm',
            .n => 'n',
            .o => 'o',
            .p => 'p',
            .q => 'q',
            .r => 'r',
            .s => 's',
            .t => 't',
            .u => 'u',
            .v => 'v',
            .w => 'w',
            .x => 'x',
            .y => 'y',
            .z => 'z',
            .zero => '0',
            .one => '1',
            .two => '2',
            .three => '3',
            .four => '4',
            .five => '5',
            .six => '6',
            .seven => '7',
            .eight => '8',
            .nine => '9',
        };
    }

    /// Single ASCII character for Windows-style shortcut display (letters uppercased).
    pub fn displayAscii(self: ShortcutKey) u8 {
        return switch (self) {
            .a => 'A',
            .b => 'B',
            .c => 'C',
            .d => 'D',
            .e => 'E',
            .f => 'F',
            .g => 'G',
            .h => 'H',
            .i => 'I',
            .j => 'J',
            .k => 'K',
            .l => 'L',
            .m => 'M',
            .n => 'N',
            .o => 'O',
            .p => 'P',
            .q => 'Q',
            .r => 'R',
            .s => 'S',
            .t => 'T',
            .u => 'U',
            .v => 'V',
            .w => 'W',
            .x => 'X',
            .y => 'Y',
            .z => 'Z',
            .zero => '0',
            .one => '1',
            .two => '2',
            .three => '3',
            .four => '4',
            .five => '5',
            .six => '6',
            .seven => '7',
            .eight => '8',
            .nine => '9',
        };
    }
};

pub const Shortcut = struct {
    key: ShortcutKey,
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
            .primary => 1 << 0,
            .super => 1 << 4,
            .shift => 1 << 1,
            .alt => 1 << 2,
            .ctrl => 1 << 3,
        };
    }
    return mask;
}

/// Builds a Windows-style shortcut label (`Ctrl+` / `Super+` / `Alt+` / `Shift+` + key). `.primary` is shown as `Ctrl+`; `.super` as `Super+` (⊞ / meta).
pub fn formatWindowsShortcut(allocator: std.mem.Allocator, shortcut: Shortcut) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    const has_primary = hasModifier(shortcut, .primary);
    const has_ctrl = hasModifier(shortcut, .ctrl);
    const has_super = hasModifier(shortcut, .super);
    if (has_primary or has_ctrl) try out.appendSlice(allocator, "Ctrl+");
    if (has_super) try out.appendSlice(allocator, "Super+");
    if (hasModifier(shortcut, .alt)) try out.appendSlice(allocator, "Alt+");
    if (hasModifier(shortcut, .shift)) try out.appendSlice(allocator, "Shift+");

    try out.append(allocator, shortcut.key.displayAscii());
    return try out.toOwnedSlice(allocator);
}

/// Shortcut text for an **in-app** menu (e.g. DVUI menubar). On macOS uses ASCII labels (`Cmd+` for [`Modifier.primary`], `Super+` for [`Modifier.super`], etc.); elsewhere same as [`formatWindowsShortcut`].
pub fn formatShortcutMenuLabel(allocator: std.mem.Allocator, shortcut: Shortcut) ![]const u8 {
    if (builtin.os.tag != .macos) {
        return try formatWindowsShortcut(allocator, shortcut);
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    if (hasModifier(shortcut, .ctrl)) try out.appendSlice(allocator, "Ctrl+");
    if (hasModifier(shortcut, .alt)) try out.appendSlice(allocator, "Opt+");
    if (hasModifier(shortcut, .shift)) try out.appendSlice(allocator, "Shift+");
    if (hasModifier(shortcut, .primary)) try out.appendSlice(allocator, "Cmd+");
    if (hasModifier(shortcut, .super)) try out.appendSlice(allocator, "Cmd+");
    try out.append(allocator, shortcut.key.displayAscii());
    return try out.toOwnedSlice(allocator);
}

fn hasModifier(shortcut: Shortcut, modifier: Modifier) bool {
    for (shortcut.modifiers) |existing| {
        if (existing == modifier) return true;
    }
    return false;
}

test "modifierMask empty" {
    const sc: Shortcut = .{ .key = .s, .modifiers = &.{} };
    try std.testing.expectEqual(@as(u32, 0), modifierMask(sc));
}

test "modifierMask primary and shift" {
    const sc: Shortcut = .{ .key = .z, .modifiers = &.{ .primary, .shift } };
    const m = modifierMask(sc);
    try std.testing.expectEqual(@as(u32, (1 << 0) | (1 << 1)), m);
}

test "modifierMask super uses bit four" {
    const sc: Shortcut = .{ .key = .s, .modifiers = &.{.super} };
    try std.testing.expectEqual(@as(u32, 1 << 4), modifierMask(sc));
}

test "formatWindowsShortcut primary maps to Ctrl" {
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .n, .modifiers = &.{.primary} };
    const s = try formatWindowsShortcut(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Ctrl+N", s);
}

test "formatWindowsShortcut super prefix" {
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .p, .modifiers = &.{.super} };
    const s = try formatWindowsShortcut(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Super+P", s);
}

test "formatWindowsShortcut modifiers order" {
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .x, .modifiers = &.{ .ctrl, .alt, .shift } };
    const s = try formatWindowsShortcut(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Ctrl+Alt+Shift+X", s);
}

test "formatShortcutMenuLabel non-macOS matches Windows style" {
    if (builtin.os.tag == .macos) return error.SkipZigTest;
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .n, .modifiers = &.{.primary} };
    const s = try formatShortcutMenuLabel(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Ctrl+N", s);
}

test "formatShortcutMenuLabel macOS primary uses Cmd label" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .n, .modifiers = &.{.primary} };
    const s = try formatShortcutMenuLabel(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Cmd+N", s);
}

test "formatShortcutMenuLabel macOS super uses Cmd label" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .p, .modifiers = &.{.super} };
    const s = try formatShortcutMenuLabel(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Cmd+P", s);
}
