const std = @import("std");

const types = @import("types.zig");

const HWND = ?*anyopaque;
const HMENU = ?*anyopaque;
const UINT = u32;
const UINT_PTR = usize;
const DWORD_PTR = usize;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const BOOL = c_int;

const MF_STRING: UINT = 0x0000;
const MF_POPUP: UINT = 0x0010;
const MF_SEPARATOR: UINT = 0x0800;
const MF_GRAYED: UINT = 0x0001;
const WM_COMMAND: UINT = 0x0111;

const command_base: u16 = 0x7000;
const subclass_id: UINT_PTR = 0x5A545241; // "ZTRA"

var pending_action_id: std.atomic.Value(c_int) = .init(-1);
var menu_installed: std.atomic.Value(bool) = .init(false);

extern "user32" fn CreateMenu() callconv(.winapi) HMENU;
extern "user32" fn CreatePopupMenu() callconv(.winapi) HMENU;
extern "user32" fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: UINT_PTR, lpNewItem: ?[*:0]const u16) callconv(.winapi) BOOL;
extern "user32" fn SetMenu(hWnd: HWND, hMenu: HMENU) callconv(.winapi) BOOL;
extern "user32" fn DrawMenuBar(hWnd: HWND) callconv(.winapi) BOOL;

extern "comctl32" fn SetWindowSubclass(
    hWnd: HWND,
    pfnSubclass: *const fn (HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR) callconv(.winapi) LRESULT,
    uIdSubclass: UINT_PTR,
    dwRefData: DWORD_PTR,
) callconv(.winapi) BOOL;
extern "comctl32" fn DefSubclassProc(hWnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;

pub fn installMainMenu(allocator: std.mem.Allocator, hwnd: HWND, menu_bar: types.MenuBar) !void {
    if (menu_installed.swap(true, .acq_rel)) return;
    if (hwnd == null) return error.MenuInstallFailed;

    const main_menu = CreateMenu() orelse return error.MenuInstallFailed;

    for (menu_bar.menus) |menu| {
        const submenu = CreatePopupMenu() orelse return error.MenuInstallFailed;

        for (menu.items) |item| {
            switch (item) {
                .separator => {
                    if (AppendMenuW(submenu, MF_SEPARATOR, 0, null) == 0) return error.MenuInstallFailed;
                },
                .action => |action| {
                    if (action.action_id < 0) return error.ActionIdOutOfRange;
                    const offset: u32 = @intCast(action.action_id);
                    if (offset > 0xFFFF - command_base) return error.ActionIdOutOfRange;

                    const title = try windowsItemTitle(allocator, action);
                    defer allocator.free(title);

                    const flags: UINT = if (action.enabled) MF_STRING else MF_STRING | MF_GRAYED;
                    if (AppendMenuW(submenu, flags, commandId(action.action_id), title.ptr) == 0) return error.MenuInstallFailed;
                },
            }
        }

        const title = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, menu.title);
        defer allocator.free(title);
        if (AppendMenuW(main_menu, MF_POPUP, @intFromPtr(submenu), title.ptr) == 0) return error.MenuInstallFailed;
    }

    if (SetMenu(hwnd, main_menu) == 0) return error.MenuInstallFailed;
    _ = DrawMenuBar(hwnd);
    if (SetWindowSubclass(hwnd, ztraySubclassProc, subclass_id, 0) == 0) return error.MenuInstallFailed;
}

pub fn pollActionId() c_int {
    return pending_action_id.swap(-1, .acq_rel);
}

fn commandId(action_id: types.ActionId) UINT_PTR {
    return command_base + @as(u16, @intCast(action_id));
}

fn actionFromCommand(command: u16) ?types.ActionId {
    if (command < command_base) return null;
    return @intCast(command - command_base);
}

fn ztraySubclassProc(
    hWnd: HWND,
    uMsg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    uIdSubclass: UINT_PTR,
    dwRefData: DWORD_PTR,
) callconv(.winapi) LRESULT {
    _ = uIdSubclass;
    _ = dwRefData;

    if (uMsg == WM_COMMAND) {
        const command: u16 = @truncate(wParam);
        if (actionFromCommand(command)) |id| {
            pending_action_id.store(id, .release);
            return 0;
        }
    }

    return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

fn windowsItemTitle(allocator: std.mem.Allocator, action: types.Item.ActionItem) ![:0]u16 {
    const label: []const u8 = blk: {
        if (action.shortcut) |shortcut| {
            if (action.shortcut_display) |d| {
                break :blk try std.fmt.allocPrint(allocator, "{s}\t{s}", .{ action.title, d });
            }
            const fmt = try types.formatWindowsShortcut(allocator, shortcut);
            defer allocator.free(fmt);
            break :blk try std.fmt.allocPrint(allocator, "{s}\t{s}", .{ action.title, fmt });
        } else {
            break :blk try allocator.dupe(u8, action.title);
        }
    };
    defer allocator.free(label);

    return std.unicode.wtf8ToWtf16LeAllocZ(allocator, label);
}
