const std = @import("std");

const dvui = @import("dvui");
const sdl3 = @import("sdl-backend").c;

const ztray = @import("main.zig");

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

pub fn installMainMenu(allocator: std.mem.Allocator, window: *dvui.Window, menu_bar: ztray.MenuBar) !void {
    if (menu_installed.swap(true, .acq_rel)) return;

    const hwnd = getHwnd(window) orelse return error.MenuInstallFailed;
    const main_menu = CreateMenu() orelse return error.MenuInstallFailed;

    for (menu_bar.menus) |menu| {
        const submenu = CreatePopupMenu() orelse return error.MenuInstallFailed;

        for (menu.items) |item| {
            switch (item) {
                .separator => {
                    if (AppendMenuW(submenu, MF_SEPARATOR, 0, null) == 0) return error.MenuInstallFailed;
                },
                .action => |action| {
                    const title = try windowsItemTitle(allocator, action);
                    defer allocator.free(title);

                    const flags: UINT = if (action.enabled) MF_STRING else MF_STRING | MF_GRAYED;
                    if (AppendMenuW(submenu, flags, commandId(action.action), title.ptr) == 0) return error.MenuInstallFailed;
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

fn getHwnd(win: *dvui.Window) HWND {
    const raw = sdl3.SDL_GetPointerProperty(
        sdl3.SDL_GetWindowProperties(win.backend.impl.window),
        sdl3.SDL_PROP_WINDOW_WIN32_HWND_POINTER,
        null,
    );
    return if (raw != null) @ptrCast(raw) else null;
}

fn commandId(action: ztray.Action) UINT_PTR {
    return command_base + @as(u16, @intCast(@intFromEnum(action)));
}

fn actionFromCommand(command: u16) ?ztray.Action {
    if (command < command_base) return null;
    const action_id = command - command_base;
    if (action_id > @intFromEnum(ztray.Action.show_dvui_demo)) return null;
    return @enumFromInt(action_id);
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
        if (actionFromCommand(command)) |action| {
            pending_action_id.store(@intFromEnum(action), .release);
            return 0;
        }
    }

    return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

fn windowsItemTitle(allocator: std.mem.Allocator, action: ztray.Item.ActionItem) ![:0]u16 {
    const title = if (action.shortcut) |shortcut|
        try std.fmt.allocPrint(allocator, "{s}\t{s}", .{ action.title, windowsShortcutLabel(shortcut) })
    else
        try allocator.dupe(u8, action.title);
    defer allocator.free(title);

    return std.unicode.wtf8ToWtf16LeAllocZ(allocator, title);
}

fn windowsShortcutLabel(shortcut: ztray.Shortcut) []const u8 {
    const command = hasModifier(shortcut, .command);
    const shift = hasModifier(shortcut, .shift);
    const control = hasModifier(shortcut, .control);

    if (command and shift and std.ascii.eqlIgnoreCase(shortcut.key, "z")) return "Ctrl+Shift+Z";
    if (command and std.ascii.eqlIgnoreCase(shortcut.key, "f")) return "Ctrl+F";
    if (command and std.ascii.eqlIgnoreCase(shortcut.key, "o")) return "Ctrl+O";
    if (command and std.ascii.eqlIgnoreCase(shortcut.key, "s")) return "Ctrl+S";
    if (command and std.ascii.eqlIgnoreCase(shortcut.key, "w")) return "Ctrl+W";
    if (command and std.ascii.eqlIgnoreCase(shortcut.key, "c")) return "Ctrl+C";
    if (command and std.ascii.eqlIgnoreCase(shortcut.key, "v")) return "Ctrl+V";
    if (command and std.ascii.eqlIgnoreCase(shortcut.key, "e")) return "Ctrl+E";
    if (control and shift and std.ascii.eqlIgnoreCase(shortcut.key, "z")) return "Ctrl+Shift+Z";
    if (control and std.ascii.eqlIgnoreCase(shortcut.key, "z")) return "Ctrl+Z";
    return shortcut.key;
}

fn hasModifier(shortcut: ztray.Shortcut, modifier: ztray.Modifier) bool {
    for (shortcut.modifiers) |existing| {
        if (existing == modifier) return true;
    }
    return false;
}
