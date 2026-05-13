//! Combined **zmenu** + optional DVUI in-app menubar. Same public surface as `zmenu.zig`; DVUI helpers live under [`dvui_menu`].
const zc = @import("zmenu_core");

pub const ActionId = zc.ActionId;
pub const ShortcutKey = zc.ShortcutKey;
pub const Shortcut = zc.Shortcut;
pub const Item = zc.Item;
pub const Menu = zc.Menu;
pub const MenuBar = zc.MenuBar;

pub const modifierMask = zc.modifierMask;
pub const formatWindowsShortcut = zc.formatWindowsShortcut;
pub const formatShortcutMenuLabel = zc.formatShortcutMenuLabel;

pub const MenuBarOptions = zc.MenuBarOptions;
pub const InstallMainMenuError = zc.InstallMainMenuError;

pub const pumpEvents = zc.pumpEvents;
pub const installMainMenu = zc.installMainMenu;
pub const appMenuRegistrarHasOwner = zc.appMenuRegistrarHasOwner;
pub const pollActionId = zc.pollActionId;
pub const pollAction = zc.pollAction;

pub const windows = zc.windows;

/// In-app DVUI menu bar (`installMainMenu`, `drawMenuBar`, `pollAction`, …).
pub const dvui_menu = @import("zmenu_dvui.zig");

pub const installMainMenuForSdlDvuiWindow = @import("zmenu_dvui.zig").installMainMenuForSdlDvuiWindow;
