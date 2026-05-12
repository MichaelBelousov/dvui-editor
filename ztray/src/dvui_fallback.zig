//! Immediate-mode menu bar using DVUI. Requires `dvui` + `sdl-backend` imports on the ztray module.
const std = @import("std");
const dvui = @import("dvui");

const types = @import("types.zig");

var pending_action: std.atomic.Value(types.ActionId) = .init(-1);

var menu_arena: std.heap.ArenaAllocator = undefined;
var menu_arena_init: bool = false;
var stored_bar: ?types.MenuBar = null;

fn dupMenuBar(parent: std.mem.Allocator, menu_bar: types.MenuBar) !types.MenuBar {
    var arena = std.heap.ArenaAllocator.init(parent);
    errdefer arena.deinit();
    const a = arena.allocator();

    var menus = try a.alloc(types.Menu, menu_bar.menus.len);
    for (menu_bar.menus, 0..) |src_menu, mi| {
        const title = try a.dupe(u8, src_menu.title);
        var items = try a.alloc(types.Item, src_menu.items.len);
        for (src_menu.items, 0..) |src_item, ii| {
            items[ii] = switch (src_item) {
                .separator => .separator,
                .action => |act| .{ .action = .{
                    .title = try a.dupe(u8, act.title),
                    .action_id = act.action_id,
                    .shortcut = act.shortcut,
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

pub fn installMainMenu(parent_allocator: std.mem.Allocator, menu_bar: types.MenuBar) !void {
    if (menu_arena_init) {
        menu_arena.deinit();
        menu_arena_init = false;
        stored_bar = null;
    }
    menu_arena = std.heap.ArenaAllocator.init(parent_allocator);
    menu_arena_init = true;
    stored_bar = try dupMenuBar(menu_arena.allocator(), menu_bar);
}

pub fn shutdownMenu() void {
    if (menu_arena_init) {
        menu_arena.deinit();
        menu_arena_init = false;
        stored_bar = null;
    }
}

fn actionLabel(allocator: std.mem.Allocator, item: types.Item.ActionItem) ![]const u8 {
    if (item.shortcut) |sc| {
        const shortcut_txt = if (item.shortcut_display) |d|
            try allocator.dupe(u8, d)
        else
            try types.formatWindowsShortcut(allocator, sc);
        defer if (item.shortcut_display == null) allocator.free(shortcut_txt);
        return try std.fmt.allocPrint(allocator, "{s}\t{s}", .{ item.title, shortcut_txt });
    }
    return try allocator.dupe(u8, item.title);
}

fn queueAction(id: types.ActionId) void {
    pending_action.store(id, .release);
}

pub fn pollActionId() ?types.ActionId {
    const v = pending_action.swap(-1, .acq_rel);
    if (v < 0) return null;
    return v;
}

/// Top bar titles: small positive ids (disjoint from [`submenuRowId`] and [`submenuPopupId`]).
fn topMenuBarItemId(menu_index: usize) usize {
    return 1 + menu_index;
}

/// Stable unique id for a row inside a top-level menu (actions and separators).
fn submenuRowId(menu_index: usize, item_index: usize) usize {
    return 0x10_0000 + menu_index * 4096 + item_index;
}

/// Per top-level menu: animate + floatingMenu share the same @src().
fn submenuPopupId(menu_index: usize, slot: u2) usize {
    return 0x20_0000 + menu_index * 8 + @as(usize, @intCast(slot));
}

/// Call every frame after [`installMainMenu`] when using forced DVUI menu mode.
pub fn drawMenuBar() !void {
    const menu_bar = stored_bar orelse return;

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
                        const label = try actionLabel(alloc, act);
                        defer alloc.free(label);

                        if (menuLeafItem(@src(), label, act.enabled, .{
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

fn menuLeafItem(src: std.builtin.SourceLocation, label_str: []const u8, enabled: bool, opts: dvui.Options) ?dvui.Rect.Natural {
    const init: dvui.MenuItemWidget.InitOptions = .{};
    var mi = dvui.menuItem(src, init, opts);
    var ret: ?dvui.Rect.Natural = null;
    if (mi.activeRect()) |r| ret = r;

    var label_opts = opts;
    label_opts.margin = dvui.Rect.all(0);
    label_opts.padding = dvui.Rect.all(0);
    if (!enabled) {
        label_opts.color_text = dvui.themeGet().color(.control, .text).opacity(0.35);
    }
    dvui.labelNoFmt(@src(), label_str, .{}, label_opts);
    mi.deinit();
    return ret;
}
