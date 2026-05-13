# ztray

Cross-platform **application menu bar** and optional **system tray** for Zig: native shell menus on macOS (AppKit `NSMenu`), Windows (Win32 `HMENU` + `comctl32` subclassing), and Linux ([DBusMenu](https://github.com/canonical/dbusmenu) over D-Bus, plus [StatusNotifierItem](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/) for tray icons). An optional **in-app** menu bar using [DVUI](https://github.com/david-vanderson/dvui) is exposed as **`ztray.dvui_menu`** when you wire the unified module from **`createZtrayDvuiModule`** (see [`ztray_with_dvui.zig`](src/ztray_with_dvui.zig) + [`ztray_dvui.zig`](src/ztray_dvui.zig)); the core module [`root.zig`](src/root.zig) never imports DVUI. Tray remains **native** even when you use the DVUI menu helper.

There is no runtime dependency on SDL or a window toolkit inside the core `ztray` sources; your app supplies a window handle on Windows when using native **menubar** integration. For **tray-only** apps on Windows, `installTrayIcon` can use an internal message-only `HWND` when `windows_hwnd` is null.

## Requirements

- **Zig** 0.16.0 or newer (see `build.zig.zon`). Zig 0.15 removed `usingnamespace`; this package uses explicit re-exports in the unified entrypoint.

## Using ztray in another project

Add a path (or fetched) dependency on this package, then **`addImport("ztray", …)`** on your app module with the same **`target`** and **`optimize`** as your executable.

- **Native menus / tray only:** call **`createZtrayModule`** from this package’s `build.zig` and pass the returned module as `ztray`.
- **Same API plus DVUI in-app menubar:** create the core module with **`createZtrayModule`**, then **`createZtrayDvuiModule(builder, target, optimize, ztray_mod, dvui_mod, sdl_mod)`** and pass that return value as your single **`addImport("ztray", …)`**. Your app uses **`ztray.dvui_menu`** for DVUI-only calls (`installMainMenu` without `hwnd`, `drawMenuBar`, …). Use **`ztray.installMainMenuForSdlDvuiWindow`** when you want native shell menus with an SDL-backed DVUI window without resolving `HWND` yourself.
- **macOS / Windows / Linux native window frame (optional, separate import):** call **`createZwindowModule`** and **`addImport("zwindow", …)`** on your app module. Pass **`ztray.ZwindowUnixBackends`** (`.x11`, `.wayland`, or `.both`) or use **`ZwindowUnixBackends.parse`** on the same comma-separated string as **`-Dzwindow_unix_backends`**. On **macOS**, use **`zwindow.setFrameChrome`** (and optionally **`zwindow.applyTransparentTitlebar`**) with an `NSWindow *` as `*anyopaque`; pass **`zwindow.FrameChromePolicy`** (e.g. **`.tray_compatible`** with a tray icon, **`.full_vibrancy`** without). On **Windows**, pass `HWND` as `*anyopaque`. On **Linux**, pass **`zwindow.LinuxFrameTarget`** as `*anyopaque` (see **`zwindow.LinuxX11WindowRef`** / **`LinuxWaylandWindowRef`**), matching [wio](https://github.com/ypsvlq/wio) `wio.backend.active`, `wio.backend.wayland.display`, and `window.backend`. Build flag **`-Dzwindow_unix_backends`** still uses the comma-separated string; the Wayland path `dlopen`s `libwayland-client.so.0` at runtime so the ztray build does not link `libwayland-client` and cross-CI from macOS stays portable. On **X11** the actual title bar is drawn by the window manager (server-side decorations), so `setFrameChrome` controls only the GTK theme variant hint, `_NET_WM_WINDOW_OPACITY` from `alpha`, and the KDE blur region. On **Wayland** zwindow clears the surface's opaque region and, when KWin advertises `org_kde_kwin_blur_manager`, attaches a blur object on `.full_vibrancy` (released on `.tray_compatible`); other compositors silently fall through. Not re-exported from the core `ztray` module. See **`zig build run-wio-window`** and **`examples/wio_window`**.

This package’s **`build.zig`** attaches the native implementation (Objective-C on macOS, `comctl32` on Windows, D-Bus menu C or stub on Linux) to the **core** `ztray` module from **`createZtrayModule`**, which **`createZtrayDvuiModule`** reuses via a `ztray_core` import—so you still do **not** list `ztray`’s `.m` / `.c` files or `dbus-1` / `comctl32` in your own `build.zig` unless you have other reasons to.

### DVUI in-app menu (optional)

The file [`ztray_dvui.zig`](src/ztray_dvui.zig) does not define the package root by itself; the build wires it under **`ztray.dvui_menu`**. Call **`ztray.dvui_menu.installMainMenu`**, **`ztray.dvui_menu.syncMenuShortcuts`** (once per install, with your [`dvui.Window`](https://github.com/david-vanderson/dvui)), **`ztray.dvui_menu.drawMenuBar`** each frame, **`ztray.dvui_menu.pollActionId`**, and **`ztray.dvui_menu.shutdownMenu`** as needed. See this repo’s `build.zig` (`createZtrayDvuiModule` + `examples/dvui_fallback/App.zig`).

On **Linux**, call **`ztray.appMenuRegistrarHasOwner()`** (session D-Bus `NameHasOwner` on `com.canonical.AppMenu.Registrar`). When it is **`false`**, there is no global AppMenu host, so native DBusMenu menubars usually do not appear in the shell—use **`ztray.dvui_menu`** for an in-app bar instead. When the result is **`null`** (D-Bus error or cross-build stub), keep your previous behavior (typically still try native). The sample enables DVUI automatically in the `false` case; **`-Dforce_dvui_menu=true`** still forces the in-app bar on every platform.

On **Windows**, pass the top-level **`HWND`** as `?*anyopaque` to **`ztray.installMainMenu`** for native menus (for example from SDL’s `SDL_PROP_WINDOW_WIN32_HWND_POINTER`), or call **`ztray.installMainMenuForSdlDvuiWindow`** from the unified module so ztray reads that property for you.

**Shortcuts in the in-app bar:** `ztray.dvui_menu` registers each item’s `shortcut` on the current [`dvui.Window.keybinds`](https://github.com/david-vanderson/dvui) map (names like `ztray_menu_{action_id}`) and dispatches key events from [`drawMenuBar`](src/ztray_dvui.zig). Call [`syncMenuShortcuts`](src/ztray_dvui.zig) once after [`installMainMenu`](src/ztray_dvui.zig) with your [`dvui.Window`](https://github.com/david-vanderson/dvui) so shortcuts work on the first frame (the sample does this). `shortcut.key` is a [`ShortcutKey`](src/types.zig) enum (letters `a`–`z`, digits `zero`–`nine`); every such key maps to a [`dvui`](https://github.com/david-vanderson/dvui) key code for registration. On macOS, avoid shortcuts that match system bindings (for example **⌘H** is usually “Hide”; use ⇧⌘H or another combo). Use [`Modifier.primary`](src/types.zig) for the usual menu accelerator (⌘ on macOS, Ctrl on Windows/Linux in DVUI); use [`Modifier.super`](src/types.zig) for the OS super / meta / ⊞ key (DVUI’s GUI modifier). The in-app menu uses [`formatShortcutMenuLabel`](src/types.zig) (`Cmd+` / `Super+` / `Opt+` on macOS, `Ctrl+` / `Super+` / `Alt+` elsewhere—ASCII). Call [`shutdownMenu`](src/ztray_dvui.zig) so those entries are removed from the window.

## API (summary)

### Public error sets

- **`InstallMainMenuError`** — All outcomes from [`installMainMenu`](src/root.zig) for **native** menus: `OutOfMemory`, `MenuInstallFailed`, `ActionIdOutOfRange`, `DBusUnavailable`, `MissingWindowsHwnd`, `UnsupportedPlatform`, `InvalidWtf8`. The **`ztray.dvui_menu`** helper’s `installMainMenu` only returns `OutOfMemory` in normal use.
- **`InstallTrayIconError`** / **`SetTrayMenuError`** — Declared on [`root.zig`](src/root.zig); Linux `setTrayMenu` never returns `InvalidWtf8`.

### Menu bar (native, core `ztray` API)

- **`installMainMenu(allocator, menu_bar, hwnd)`** — Install **native** shell menus. `hwnd` is required on Windows; ignored on macOS; unused on Linux for D-Bus registration. On platforms outside macOS / Windows / Linux, returns `error.UnsupportedPlatform`.
- **`appMenuRegistrarHasOwner()`** — Linux only: `true` / `false` if the session bus reports an owner for `com.canonical.AppMenu.Registrar`; `null` on other OS tags, on D-Bus failure, or when built with the non-Linux cross stub. Use with DVUI to decide an in-app menubar fallback (see DVUI subsection above).
- **`pollActionId()`** — Returns the last **native** menubar action id, or `null` (cleared on read).

### DVUI in-app menu (`ztray.dvui_menu`, optional)

- **`installMainMenu`**, **`syncMenuShortcuts`**, **`drawMenuBar`**, **`pollActionId`**, **`shutdownMenu`** — Same menu model as `ztray.MenuBar` / `ztray.ActionId`, rendered inside DVUI. Does not replace native `installMainMenu` unless you choose not to call the latter. Menu shortcuts are registered on [`dvui.Window.keybinds`](https://github.com/david-vanderson/dvui) and handled while `drawMenuBar` runs; call `syncMenuShortcuts` after `installMainMenu` so keys work on the first frame; call `shutdownMenu` to remove them.

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
zig build ci     # cross-builds examples (Linux zwindow matrix: x11 / wayland / both per arch)
```

### Build option

| Flag | Meaning |
|------|---------|
| `-Dforce_dvui_menu=true` | **DVUI sample only** (`ztray-dvui`): in-app DVUI menubar via `ztray.dvui_menu`; default is **native** shell menu for that sample. |
| `-Dzwindow_unix_backends` | **zwindow** on Linux: comma list **`x11`**, **`wayland`** (default **`x11,wayland`**). Matches the idea of wio’s **`-Dunix_backends`** when trimming backends. |

Option names use **underscores** (Zig’s `zig build -D` convention), e.g. `-Dforce_dvui_menu=true`.

### Examples (installed by `zig build`)

| Artifact | Step | Notes |
|----------|------|--------|
| `ztray-dvui` | `zig build run-dvui` | DVUI window + ztray; native menubar by default, or `-Dforce_dvui_menu=true` for in-app bar (`ztray.dvui_menu`). |
| `ztray-wio-native` | `zig build run-wio` | [wio](https://github.com/ypsvlq/wio) window + native ztray menus only. |
| `ztray-wio-tray` | `zig build run-wio-tray` | wio + native menubar + tray. **`zwindow.setFrameChrome`** after install (`.tray_compatible` on macOS; Windows ignores policy; Linux uses **`LinuxFrameTarget`**). |
| `ztray-wio-window` | `zig build run-wio-window` | wio + **`zwindow.setFrameChrome`** with **`.full_vibrancy`** on macOS; Linux uses **`LinuxFrameTarget`**; other hosts plain wio. Source: `examples/wio_window`. |
| `ztray-tray-minimal` | `zig build run-tray` | Tray icon + context menu only (message-only HWND on Windows). |

On **Linux**, the wio and tray examples are linked **dynamically** where applicable (wio’s default Unix path expects dynamic linking when system integration is off).

## Layout

- `src/root.zig` — Public API and OS dispatch (menubar + tray).
- `src/types.zig` — Menu types and shortcuts.
- `src/macos_menu.m` / `src/macos_tray.m` — AppKit menubar and status item tray.
- `src/linux_dbus_menu.c` — Session D-Bus menubar + tray (DBusMenu + StatusNotifierItem when built on Linux).
- `src/ztray_with_dvui.zig` — Unified module root when using `createZtrayDvuiModule` (re-exports core + `dvui_menu`).
- `src/ztray_dvui.zig` — DVUI menubar implementation (imported as `ztray.dvui_menu`).
- `examples/` — Sample apps.
- `src/window_root.zig` / `src/window_linux*.zig` — Optional **`zwindow`** module (macOS / Windows / Linux frame chrome).
