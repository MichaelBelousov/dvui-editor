//! In-app menu bar using DVUI. Included as [`ztray.dvui_menu`] when using `createZtrayDvuiModule` (single `ztray` import).
//! This file expects build imports `ztray_core` (same API as core `ztray`) and `dvui`.
const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const ztray = @import("ztray_core");

var pending_action: std.atomic.Value(ztray.ActionId) = .init(-1);

var menu_arena: std.heap.ArenaAllocator = undefined;
var menu_arena_init: bool = false;
var stored_bar: ?ztray.MenuBar = null;

/// Bumped on each successful [`installMainMenu`]; when it differs from `synced_serial`, keybinds are refreshed.
var menu_serial: u32 = 0;
var synced_serial: u32 = 0;

/// Action ids that have a shortcut registered on [`dvui.Window.keybinds`] (for removal and dispatch).
const max_shortcut_slots = 128;
var shortcut_ids_storage: [max_shortcut_slots]ztray.ActionId = undefined;
var shortcut_ids_len: usize = 0;

/// Last window used to register keybinds; used by [`shutdownMenu`] to remove entries.
var last_win: ?*dvui.Window = null;

fn dupMenuBar(a: std.mem.Allocator, menu_bar: ztray.MenuBar) !ztray.MenuBar {
    var menus = try a.alloc(ztray.Menu, menu_bar.menus.len);
    for (menu_bar.menus, 0..) |src_menu, mi| {
        const title = try a.dupe(u8, src_menu.title);
        var items = try a.alloc(ztray.Item, src_menu.items.len);
        for (src_menu.items, 0..) |src_item, ii| {
            items[ii] = switch (src_item) {
                .separator => .separator,
                .action => |act| .{ .action = .{
                    .title = try a.dupe(u8, act.title),
                    .action_id = act.action_id,
                    .shortcut = if (act.shortcut) |sc| ztray.Shortcut{
                        .key = sc.key,
                        .modifiers = try a.dupe(ztray.Modifier, sc.modifiers),
                    } else null,
                    .shortcut_display = if (act.shortcut_display) |sd| try a.dupe(u8, sd) else null,
                    .enabled = act.enabled,
                    .suppress_next_window_close = act.suppress_next_window_close,
                } },
            };
        }
        menus[mi] = .{ .title = title, .items = items };
    }

    return .{ .menus = menus };
}

pub fn installMainMenu(parent_allocator: std.mem.Allocator, menu_bar: ztray.MenuBar) error{OutOfMemory}!void {
    // Remove DVUI keybinds from the previous menu before dropping stored_bar (names come from shortcut_ids_storage).
    if (last_win) |win| {
        removeRegisteredKeybinds(win);
        last_win = null;
    }
    shortcut_ids_len = 0;
    synced_serial = 0;

    if (menu_arena_init) {
        menu_arena.deinit();
        menu_arena_init = false;
        stored_bar = null;
    }
    menu_arena = std.heap.ArenaAllocator.init(parent_allocator);
    menu_arena_init = true;
    errdefer {
        menu_arena.deinit();
        menu_arena_init = false;
    }
    stored_bar = try dupMenuBar(menu_arena.allocator(), menu_bar);
    menu_serial +%= 1;
}

pub fn shutdownMenu() void {
    if (last_win) |win| {
        removeRegisteredKeybinds(win);
        last_win = null;
    }
    shortcut_ids_len = 0;
    synced_serial = 0;
    if (menu_arena_init) {
        menu_arena.deinit();
        menu_arena_init = false;
        stored_bar = null;
    }
}

fn menuBindName(buf: *[64]u8, action_id: ztray.ActionId) []const u8 {
    return std.fmt.bufPrint(buf[0..], "ztray_menu_{d}", .{action_id}) catch unreachable;
}

fn removeRegisteredKeybinds(win: *dvui.Window) void {
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < shortcut_ids_len) : (i += 1) {
        const name = menuBindName(&buf, shortcut_ids_storage[i]);
        _ = win.keybinds.remove(name);
    }
}

fn shortcutKeyToDvuiKey(key: ztray.ShortcutKey) dvui.enums.Key {
    return switch (key) {
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,
        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,
    };
}

fn shortcutToKeybind(sc: ztray.Shortcut) dvui.enums.Keybind {
    const key = shortcutKeyToDvuiKey(sc.key);
    var kb: dvui.enums.Keybind = .{ .key = key };

    var has_primary = false;
    var has_super = false;
    var has_ctrl = false;
    for (sc.modifiers) |m| {
        switch (m) {
            .primary => has_primary = true,
            .super => has_super = true,
            .ctrl => has_ctrl = true,
            .shift => kb.shift = true,
            .alt => kb.alt = true,
        }
    }
    if (has_ctrl) kb.control = true;
    if (has_primary) {
        if (builtin.os.tag == .macos) {
            kb.command = true;
        } else {
            kb.control = true;
        }
    }
    if (has_super) {
        kb.command = true;
    }
    return kb;
}

/// Registers menu shortcuts on [`dvui.Window.keybinds`]. Call after [`installMainMenu`] (e.g. from your window init) so keys work on the first frame; [`drawMenuBar`] also syncs when the menu changes.
pub fn syncMenuShortcuts(win: *dvui.Window) !void {
    try syncMenuKeybinds(win);
}

fn syncMenuKeybinds(win: *dvui.Window) !void {
    if (menu_serial == synced_serial) return;

    removeRegisteredKeybinds(win);
    shortcut_ids_len = 0;

    const mb = stored_bar orelse return;

    var buf: [64]u8 = undefined;
    for (mb.menus) |menu| {
        for (menu.items) |item| {
            switch (item) {
                .separator => {},
                .action => |act| {
                    if (!act.enabled) continue;
                    const sc = act.shortcut orelse continue;
                    const kb = shortcutToKeybind(sc);
                    const name = try std.fmt.bufPrint(buf[0..], "ztray_menu_{d}", .{act.action_id});
                    try win.keybinds.put(win.gpa, name, kb);
                    if (shortcut_ids_len >= shortcut_ids_storage.len) return error.OutOfMemory;
                    shortcut_ids_storage[shortcut_ids_len] = act.action_id;
                    shortcut_ids_len += 1;
                },
            }
        }
    }
    synced_serial = menu_serial;
    last_win = win;
}

fn dispatchMenuShortcuts() void {
    var keybind_buf: [64]u8 = undefined;
    for (dvui.events()) |*e| {
        if (e.handled) continue;
        switch (e.evt) {
            .key => |ke| {
                if (ke.action != .down and ke.action != .repeat) continue;
                var i: usize = 0;
                while (i < shortcut_ids_len) : (i += 1) {
                    const name = menuBindName(&keybind_buf, shortcut_ids_storage[i]);
                    if (ke.matchBind(name)) {
                        queueAction(shortcut_ids_storage[i]);
                        break;
                    }
                }
            },
            else => {},
        }
    }
}

fn bracketedShortcutText(allocator: std.mem.Allocator, item: ztray.Item.ActionItem) error{OutOfMemory}!?[]const u8 {
    const sc = item.shortcut orelse return null;
    const shortcut_txt = if (item.shortcut_display) |d|
        d
    else
        try ztray.formatShortcutMenuLabel(allocator, sc);
    defer if (item.shortcut_display == null) allocator.free(shortcut_txt);
    return try std.fmt.allocPrint(allocator, "[{s}]", .{shortcut_txt});
}

fn queueAction(id: ztray.ActionId) void {
    pending_action.store(id, .release);
}

pub fn pollActionId() ?ztray.ActionId {
    const v = pending_action.swap(-1, .acq_rel);
    if (v < 0) return null;
    return v;
}

fn topMenuBarItemId(menu_index: usize) usize {
    return 1 + menu_index;
}

fn submenuRowId(menu_index: usize, item_index: usize) usize {
    return 0x10_0000 + menu_index * 4096 + item_index;
}

fn submenuPopupId(menu_index: usize, slot: u2) usize {
    return 0x20_0000 + menu_index * 8 + @as(usize, @intCast(slot));
}

/// Call every frame after [`installMainMenu`] while using the DVUI menu bar.
pub fn drawMenuBar() !void {
    const menu_bar = stored_bar orelse return;

    const win = dvui.currentWindow();
    try syncMenuKeybinds(win);
    dispatchMenuShortcuts();

    const bg_box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal, .background = false, .color_fill = dvui.themeGet().color(.control, .fill) });
    defer bg_box.deinit();

    var m = dvui.menu(@src(), .horizontal, .{});
    defer m.deinit();

    const current_highlight_style = dvui.themeGet().highlight;
    var theme = dvui.themeGet();
    theme.highlight.fill = theme.color(.control, .fill_hover);
    dvui.themeSet(theme);
    defer {
        theme.highlight = current_highlight_style;
        dvui.themeSet(theme);
    }

    const alloc = menu_arena.allocator();

    for (menu_bar.menus, 0..) |menu, mi| {
        if (menuItemTop(@src(), menu.title, .{ .submenu = true }, .{
            .expand = .horizontal,
            .color_text = dvui.themeGet().color(.control, .text),
            .id_extra = topMenuBarItemId(mi),
        })) |r| {
            var animator = dvui.animate(@src(), .{
                .kind = .alpha,
                .duration = 250_000,
            }, .{
                .expand = .both,
                .id_extra = submenuPopupId(mi, 0),
            });
            defer animator.deinit();

            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{
                .id_extra = submenuPopupId(mi, 1),
            });
            defer fw.deinit();

            for (menu.items, 0..) |item, ii| {
                const row_id = submenuRowId(mi, ii);
                switch (item) {
                    .separator => {
                        _ = dvui.separator(@src(), .{ .expand = .horizontal, .id_extra = row_id });
                    },
                    .action => |act| {
                        const shortcut_bracketed = try bracketedShortcutText(alloc, act);
                        defer if (shortcut_bracketed) |s| alloc.free(s);

                        if (menuLeafAction(@src(), act.title, shortcut_bracketed, act.enabled, .{
                            .expand = .horizontal,
                            .id_extra = row_id,
                        }) != null) {
                            if (act.enabled) {
                                queueAction(act.action_id);
                                fw.close();
                            }
                        }
                    },
                }
            }
        }
    }
}

fn menuItemTop(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: dvui.MenuItemWidget.InitOptions, opts: dvui.Options) ?dvui.Rect.Natural {
    var mi = dvui.menuItem(src, init_opts, opts);
    var ret: ?dvui.Rect.Natural = null;
    if (mi.activeRect()) |r| ret = r;

    var label_opts = opts;
    label_opts.margin = dvui.Rect.all(0);
    label_opts.padding = dvui.Rect.all(0);
    dvui.labelNoFmt(@src(), label_str, .{}, label_opts);
    mi.deinit();
    return ret;
}

fn menuLeafAction(src: std.builtin.SourceLocation, title: []const u8, shortcut_bracketed: ?[]const u8, enabled: bool, opts: dvui.Options) ?dvui.Rect.Natural {
    const init: dvui.MenuItemWidget.InitOptions = .{};
    var mi = dvui.menuItem(src, init, opts);
    defer mi.deinit();
    var ret: ?dvui.Rect.Natural = null;
    if (mi.activeRect()) |r| ret = r;

    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .expand = .horizontal,
        .margin = dvui.Rect.all(0),
        .padding = dvui.Rect.all(0),
    });
    defer row.deinit();

    var title_opts = opts.strip();
    title_opts.expand = .none;
    title_opts.margin = dvui.Rect.all(0);
    title_opts.padding = dvui.Rect.all(0);
    title_opts.gravity_y = 0.5;
    if (!enabled) {
        title_opts.color_text = dvui.themeGet().color(.control, .text).opacity(0.35);
    }
    dvui.labelNoFmt(@src(), title, .{}, title_opts);

    if (shortcut_bracketed) |sc| {
        _ = dvui.spacer(@src(), .{ .min_size_content = .width(10) });
        _ = dvui.spacer(@src(), .{ .expand = .horizontal });

        var sc_opts = opts.strip();
        sc_opts.expand = .none;
        sc_opts.margin = dvui.Rect.all(0);
        sc_opts.padding = dvui.Rect.all(0);
        sc_opts.gravity_y = 0.5;
        const base = dvui.themeGet().color(.control, .text);
        sc_opts.color_text = if (enabled) base.opacity(0.48) else base.opacity(0.28);
        dvui.labelNoFmt(@src(), sc, .{}, sc_opts);
    }

    return ret;
}

/// Installs the native shell menu for an SDL-backed DVUI window (resolves `HWND` on Windows from SDL window properties).
pub fn installMainMenuForSdlDvuiWindow(allocator: std.mem.Allocator, menu_bar: ztray.MenuBar, win: *dvui.Window) ztray.InstallMainMenuError!void {
    const hwnd = if (builtin.os.tag == .windows) blk: {
        const sdl3 = @import("sdl-backend").c;
        const raw = sdl3.SDL_GetPointerProperty(
            sdl3.SDL_GetWindowProperties(win.backend.impl.window),
            sdl3.SDL_PROP_WINDOW_WIN32_HWND_POINTER,
            null,
        );
        break :blk if (raw != null) @as(?*anyopaque, @ptrCast(raw)) else null;
    } else null;
    return ztray.installMainMenu(allocator, menu_bar, hwnd);
}
