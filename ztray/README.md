# ztray

Cross-platform **application menu bar** and optional **system tray** for Zig: native shell menus on macOS (AppKit `NSMenu`), Windows (Win32 `HMENU` + `comctl32` subclassing), and Linux ([DBusMenu](https://github.com/canonical/dbusmenu) over D-Bus, plus [StatusNotifierItem](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/) for tray icons). An optional **in-app** menu bar using [DVUI](https://github.com/david-vanderson/dvui) lives in a **separate** module [`ztray_dvui.zig`](src/ztray_dvui.zig) so the core **`ztray`** module never depends on DVUI. Tray remains **native** even when you use the DVUI menu helper.

There is no runtime dependency on SDL or a window toolkit inside the core `ztray` sources; your app supplies a window handle on Windows when using native **menubar** integration. For **tray-only** apps on Windows, `installTrayIcon` can use an internal message-only `HWND` when `windows_hwnd` is null.

## Requirements

- **Zig** 0.16.0 or newer (see `build.zig.zon`).

## Using ztray in another project

Add a path (or fetched) dependency on this package, then **`addImport("ztray", dep.module("ztray"))`** on your app module with the same **`target`** and **`optimize`** as your executable.

This package’s **`build.zig`** attaches the native implementation (Objective-C on macOS, `comctl32` on Windows, D-Bus menu C or stub on Linux) to the **`ztray` module** itself, so you do **not** list `ztray`’s `.m` / `.c` files or `dbus-1` / `comctl32` in your own `build.zig` unless you have other reasons to.

### DVUI in-app menu (optional)

The core module does **not** import DVUI. To draw a menubar inside a DVUI app, add a second module whose root is `ztray/src/ztray_dvui.zig`, import **`ztray`** and **`dvui`** into it, then call `ztray_dvui.installMainMenu`, `ztray_dvui.drawMenuBar` each frame, `ztray_dvui.pollActionId`, and `ztray_dvui.shutdownMenu` as needed. See this repo’s `build.zig` (`createZtrayDvuiModule` + `examples/dvui_fallback/App.zig`).

On **Windows**, pass the top-level **`HWND`** as `?*anyopaque` to **`ztray.installMainMenu`** for native menus (for example from SDL’s `SDL_PROP_WINDOW_WIN32_HWND_POINTER`).

## API (summary)

### Public error sets

- **`InstallMainMenuError`** — All outcomes from [`installMainMenu`](src/root.zig) for **native** menus: `OutOfMemory`, `MenuInstallFailed`, `ActionIdOutOfRange`, `DBusUnavailable`, `MissingWindowsHwnd`, `UnsupportedPlatform`, `InvalidWtf8`. The separate **`ztray_dvui`** helper’s `installMainMenu` only returns `OutOfMemory` in normal use.
- **`InstallTrayIconError`** / **`SetTrayMenuError`** — Declared on [`root.zig`](src/root.zig); Linux `setTrayMenu` never returns `InvalidWtf8`.

### Menu bar (native, `ztray` module)

- **`installMainMenu(allocator, menu_bar, hwnd)`** — Install **native** shell menus. `hwnd` is required on Windows; ignored on macOS; unused on Linux for D-Bus registration. On platforms outside macOS / Windows / Linux, returns `error.UnsupportedPlatform`.
- **`pollActionId()`** — Returns the last **native** menubar action id, or `null` (cleared on read).
- **`consumeCloseTabSuppression()`** — macOS helper for “close tab” style items that suppress the next window close.

### DVUI in-app menu (`ztray_dvui` module, optional)

- **`ztray_dvui.installMainMenu`**, **`drawMenuBar`**, **`pollActionId`**, **`shutdownMenu`** — Same menu model as `ztray.MenuBar` / `ztray.ActionId`, rendered inside DVUI. Does not replace native `installMainMenu` unless you choose not to call the latter.

### System tray (orthogonal to the menu bar)

- **`TrayMenu`** — Alias of [`Menu`](src/types.zig); same `Item` / `ActionId` model as submenus. Root `title` is mainly relevant on Linux (DBus layout).
- **`installTrayIcon(allocator, options: TrayIconOptions)`** — Native tray icon. On Windows, `options.windows_hwnd == null` uses a message-only window so tray-only binaries work without a UI toolkit.
- **`setTrayMenu(allocator, menu: TrayMenu)`** — Attach or replace the tray context menu (independent of `installMainMenu`). On Linux, if the tray was not installed first, returns `error.MenuInstallFailed` (same idea as macOS when the tray session is inactive).
- **`pollTrayActionId()`** — Like `pollActionId`, but only for tray menu actions (separate queue from the menubar).
- **`pumpTrayEvents()`** — Linux: D-Bus dispatch. macOS: short `NSApplication` event slice. Windows: `PeekMessage` / `DispatchMessage` for the tray HWND (call regularly from your loop).
- **`shutdownTray()`** — Remove the tray icon and release tray resources.

### Threading, event loops, and strings

Use the **main / UI thread** for `installMainMenu`, `installTrayIcon`, and `setTrayMenu`. Pump the platform message loop (or call `pumpTrayEvents` for tray-only Windows apps) from that thread.

On **Linux**, `pollActionId`, `pollTrayActionId`, and `pumpTrayEvents` all run D-Bus dispatch on the same connection; calling several per frame is redundant but safe.

Menu titles and shortcuts are **copied** when menus are installed. After a successful `installMainMenu` or `setTrayMenu`, you may free your `Menu` / `MenuBar` data.

### Windows `action_id` range

Menubar and tray command ids use separate bases on Win32. Use non-negative ids no larger than:

| Surface | Constant (re-exported from `ztray`) | Decimal |
|---------|-------------------------------------|---------|
| Menubar | `windows_menubar_action_id_max` | 36863 |
| Tray popup | `windows_tray_action_id_max` | 35455 |

(`src/windows.zig` defines the same limits as `menubar_action_id_max` / `tray_action_id_max`.)

### Tray icon options by OS

| Field | macOS | Windows | Linux |
|-------|-------|---------|-------|
| `icon_png` | Preferred if set | Preferred if set | Ignored (use `linux_icon_name`) |
| `icon_file` | Fallback path | Fallback `.ico` / image path | Used if `linux_icon_name` is null (name/path for SNI) |
| `linux_icon_name` | — | — | Freedesktop **IconName** for StatusNotifierItem |

The DVUI sample in this repo uses a generated options module **`ztray_dvui_opts`** (`force_dvui_menu` only); the **`ztray`** module itself has no build-options import.

## Building this package

From the `ztray/` directory:

```sh
zig fetch   # resolves lazy dependencies (dvui, wio) for examples
zig build
zig build test   # unit tests (types / pure helpers)
```

### Build option

| Flag | Meaning |
|------|---------|
| `-Dforce_dvui_menu=true` | **DVUI sample only** (`ztray-dvui`): in-app DVUI menubar via `ztray_dvui`; default is **native** shell menu for that sample. |

Option names use **underscores** (Zig’s `zig build -D` convention), e.g. `-Dforce_dvui_menu=true`.

### Examples (installed by `zig build`)

| Artifact | Step | Notes |
|----------|------|--------|
| `ztray-dvui` | `zig build run-dvui` | DVUI window + ztray; native menubar by default, or `-Dforce_dvui_menu=true` for in-app bar (`ztray_dvui`). |
| `ztray-wio-native` | `zig build run-wio` | [wio](https://github.com/ypsvlq/wio) window + native ztray menus only. |
| `ztray-wio-tray` | `zig build run-wio-tray` | wio window + native menubar + system tray (`windows_hwnd` = main window on Windows). |
| `ztray-tray-minimal` | `zig build run-tray` | Tray icon + context menu only (message-only HWND on Windows). |

On **Linux**, the wio and tray examples are linked **dynamically** where applicable (wio’s default Unix path expects dynamic linking when system integration is off).

## Layout

- `src/root.zig` — Public API and OS dispatch (menubar + tray).
- `src/types.zig` — Menu types and shortcuts.
- `src/macos_menu.m` / `src/macos_tray.m` — AppKit menubar and status item tray.
- `src/linux_dbus_menu.c` — Session D-Bus menubar + tray (DBusMenu + StatusNotifierItem when built on Linux).
- `src/ztray_dvui.zig` — Optional DVUI menubar helper (separate module; import only with DVUI).
- `examples/` — Sample apps.

## License

Follow the license of the repository that contains this package (or add a dedicated license file here if you publish `ztray` standalone).
