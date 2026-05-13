//! Combined **ztray** + optional DVUI in-app menubar. Same public surface as [`root.zig`](root.zig); DVUI helpers live under [`dvui_menu`].
//!
//! Wire with `createZtrayDvuiModule` from this package’s `build.zig`: one `addImport("ztray", …)` for your app root (pass SDL module as in `build.zig`). Use [`dvui_menu`] for `installMainMenu` / `drawMenuBar` / `pollActionId` / etc. that target DVUI (signatures differ from native [`installMainMenu`] / [`pollActionId`] on the core re-exports).

const zc = @import("ztray_core");

pub const ActionId = zc.ActionId;
pub const Modifier = zc.Modifier;
pub const ShortcutKey = zc.ShortcutKey;
pub const Shortcut = zc.Shortcut;
pub const Item = zc.Item;
pub const Menu = zc.Menu;
pub const MenuBar = zc.MenuBar;
pub const TrayMenu = zc.TrayMenu;

pub const zig_favicon_png = zc.zig_favicon_png;

pub const modifierMask = zc.modifierMask;
pub const formatWindowsShortcut = zc.formatWindowsShortcut;
pub const formatShortcutMenuLabel = zc.formatShortcutMenuLabel;

pub const TrayIconOptions = zc.TrayIconOptions;
pub const MenuBarOptions = zc.MenuBarOptions;

pub const InstallTrayIconError = zc.InstallTrayIconError;
pub const SetTrayMenuError = zc.SetTrayMenuError;
pub const InstallMainMenuError = zc.InstallMainMenuError;

pub const pumpEvents = zc.pumpEvents;
pub const pumpTrayEvents = zc.pumpTrayEvents;
pub const installMainMenu = zc.installMainMenu;
pub const appMenuRegistrarHasOwner = zc.appMenuRegistrarHasOwner;
pub const pollActionId = zc.pollActionId;
pub const installTrayIcon = zc.installTrayIcon;
pub const setTrayMenu = zc.setTrayMenu;
pub const pollTrayActionId = zc.pollTrayActionId;
pub const shutdownTray = zc.shutdownTray;

pub const windows = zc.windows;
pub const windows_menubar_action_id_max = zc.windows_menubar_action_id_max;
pub const windows_tray_action_id_max = zc.windows_tray_action_id_max;

/// In-app menu bar using DVUI (`installMainMenu` without `hwnd`, `drawMenuBar`, …).
pub const dvui_menu = @import("ztray_dvui.zig");

pub const installMainMenuForSdlDvuiWindow = @import("ztray_dvui.zig").installMainMenuForSdlDvuiWindow;
