const std = @import("std");
const builtin = @import("builtin");

pub const ActionId = c_int;

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

    /// Lowercase letter byte or digit char for AppKit `keyEquivalent` / C string.
    pub fn keyEquivalentByte(self: ShortcutKey) u8 {
        const n = @tagName(self);
        if (n.len == 1) return n[0]; // letters 'a'..'z'
        const digit_names = [10][]const u8{ "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" };
        for (digit_names, 0..) |name, i| {
            if (std.mem.eql(u8, n, name)) return '0' + @as(u8, @intCast(i));
        }
        unreachable;
    }

    /// Single ASCII char for Windows-style shortcut display (letters uppercased).
    pub fn displayAscii(self: ShortcutKey) u8 {
        const b = self.keyEquivalentByte();
        return if (b >= 'a') b - 32 else b;
    }
};

/// Menu keyboard shortcut. All modifier fields default to `false`.
pub const Shortcut = struct {
    key: ShortcutKey,
    /// ⌘ on macOS native menus; Ctrl on Windows/Linux (typical "File → New" chord).
    primary: bool = false,
    shift: bool = false,
    /// Alt on Windows/Linux; Option on macOS.
    alt: bool = false,
    /// Explicit Ctrl (e.g. for Ctrl+Alt combos distinct from primary).
    ctrl: bool = false,
    /// OS super / meta / Windows (⊞) key. macOS maps this to Command (no separate ⊞ in AppKit).
    super: bool = false,
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
    };
};

pub const Menu = struct {
    title: []const u8,
    items: []const Item,
};

pub const MenuBar = struct {
    menus: []const Menu,
};

/// Bitmask of active modifiers for ObjC `keyEquivalentModifierMask` and Windows accelerator formatting.
pub fn modifierMask(shortcut: Shortcut) u32 {
    var mask: u32 = 0;
    if (shortcut.primary) mask |= 1 << 0;
    if (shortcut.shift)   mask |= 1 << 1;
    if (shortcut.alt)     mask |= 1 << 2;
    if (shortcut.ctrl)    mask |= 1 << 3;
    if (shortcut.super)   mask |= 1 << 4;
    return mask;
}

/// Builds a Windows-style shortcut label (`Ctrl+` / `Super+` / `Alt+` / `Shift+` + key).
pub fn formatWindowsShortcut(allocator: std.mem.Allocator, shortcut: Shortcut) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    if (shortcut.primary or shortcut.ctrl) try out.appendSlice(allocator, "Ctrl+");
    if (shortcut.super) try out.appendSlice(allocator, "Super+");
    if (shortcut.alt) try out.appendSlice(allocator, "Alt+");
    if (shortcut.shift) try out.appendSlice(allocator, "Shift+");
    try out.append(allocator, shortcut.key.displayAscii());
    return try out.toOwnedSlice(allocator);
}

/// Shortcut text for an **in-app** menu (e.g. DVUI menubar). On macOS uses `Cmd+`/`Opt+`; elsewhere same as [`formatWindowsShortcut`].
pub fn formatShortcutMenuLabel(allocator: std.mem.Allocator, shortcut: Shortcut) ![]const u8 {
    if (builtin.os.tag != .macos) return try formatWindowsShortcut(allocator, shortcut);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    if (shortcut.ctrl) try out.appendSlice(allocator, "Ctrl+");
    if (shortcut.alt) try out.appendSlice(allocator, "Opt+");
    if (shortcut.shift) try out.appendSlice(allocator, "Shift+");
    if (shortcut.primary) try out.appendSlice(allocator, "Cmd+");
    if (shortcut.super) try out.appendSlice(allocator, "Cmd+");
    try out.append(allocator, shortcut.key.displayAscii());
    return try out.toOwnedSlice(allocator);
}

test "modifierMask empty" {
    const sc: Shortcut = .{ .key = .s };
    try std.testing.expectEqual(@as(u32, 0), modifierMask(sc));
}

test "modifierMask primary and shift" {
    const sc: Shortcut = .{ .key = .z, .primary = true, .shift = true };
    const m = modifierMask(sc);
    try std.testing.expectEqual(@as(u32, (1 << 0) | (1 << 1)), m);
}

test "modifierMask super uses bit four" {
    const sc: Shortcut = .{ .key = .s, .super = true };
    try std.testing.expectEqual(@as(u32, 1 << 4), modifierMask(sc));
}

test "formatWindowsShortcut primary maps to Ctrl" {
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .n, .primary = true };
    const s = try formatWindowsShortcut(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Ctrl+N", s);
}

test "formatWindowsShortcut super prefix" {
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .p, .super = true };
    const s = try formatWindowsShortcut(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Super+P", s);
}

test "formatWindowsShortcut modifiers order" {
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .x, .ctrl = true, .alt = true, .shift = true };
    const s = try formatWindowsShortcut(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Ctrl+Alt+Shift+X", s);
}

test "formatShortcutMenuLabel non-macOS matches Windows style" {
    if (builtin.os.tag == .macos) return error.SkipZigTest;
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .n, .primary = true };
    const s = try formatShortcutMenuLabel(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Ctrl+N", s);
}

test "formatShortcutMenuLabel macOS primary uses Cmd label" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .n, .primary = true };
    const s = try formatShortcutMenuLabel(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Cmd+N", s);
}

test "formatShortcutMenuLabel macOS super uses Cmd label" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const ally = std.testing.allocator;
    const sc: Shortcut = .{ .key = .p, .super = true };
    const s = try formatShortcutMenuLabel(ally, sc);
    defer ally.free(s);
    try std.testing.expectEqualStrings("Cmd+P", s);
}
