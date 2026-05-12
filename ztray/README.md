# ztray

Cross-platform **application menu bar** and optional **system tray** for Zig: native shell menus on macOS (AppKit `NSMenu`), Windows (Win32 `HMENU` + `comctl32` subclassing), and Linux ([DBusMenu](https://github.com/canonical/dbusmenu) over D-Bus, plus [StatusNotifierItem](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/) for tray icons). Optional **in-app** menu bar using [DVUI](https://github.com/david-vanderson/dvui) when you compile with `force_dvui_menu` enabled (see below). Tray remains **native** even when the DVUI menu bar is forced.

There is no runtime dependency on SDL or a window toolkit inside the core `ztray` sources; your app supplies a window handle on Windows when using native **menubar** integration. For **tray-only** apps on Windows, `installTrayIcon` can use an internal message-only `HWND` when `windows_hwnd` is null.

## Requirements

- **Zig** 0.16.0 or newer (see `build.zig.zon`).

## Using ztray in another project

Add a path (or fetched) dependency on this package, then **`addImport("ztray", dep.module("ztray"))`** on your app module. Use the same **`target`** and **`optimize`** as your executable, and set **`force_dvui_menu`** on the dependency if you want the in-app DVUI menu path instead of native shell menus.

This package’s **`build.zig`** attaches the native implementation (Objective-C on macOS, `comctl32` on Windows, D-Bus menu C or stub on Linux) to the **`ztray` module** itself, so you do **not** list `ztray`’s `.m` / `.c` files or `dbus-1` / `comctl32` in your own `build.zig` unless you have other reasons to.

On **Windows**, pass the top-level **`HWND`** as `?*anyopaque` to `installMainMenu` (for example from SDL’s `SDL_PROP_WINDOW_WIN32_HWND_POINTER`).

## API (summary)

### Menu bar

- **`installMainMenu(allocator, menu_bar, hwnd)`** — Install menus. `hwnd` is required on Windows for native menus; ignored on macOS; unused on Linux for D-Bus registration.
- **`pollActionId()`** — Returns the last **menubar** menu action id, or `null` (cleared on read).
- **`drawMenuBar()`** — Only when compile-time **`force_dvui_menu`** is set: call each frame from your DVUI tick to draw the in-app menu bar.
- **`shutdownDvuiMenu()`** — Release DVUI fallback menu storage when applicable.
- **`consumeCloseTabSuppression()`** — macOS helper for “close tab” style items that suppress the next window close.

### System tray (orthogonal to the menu bar)

- **`TrayMenu`** — Alias of [`Menu`](src/types.zig); same `Item` / `ActionId` model as submenus. Root `title` is mainly relevant on Linux (DBus layout).
- **`installTrayIcon(allocator, options: TrayIconOptions)`** — Native tray icon. On Windows, `options.windows_hwnd == null` uses a message-only window so tray-only binaries work without a UI toolkit.
- **`setTrayMenu(allocator, menu: TrayMenu)`** — Attach or replace the tray context menu (independent of `installMainMenu`).
- **`pollTrayActionId()`** — Like `pollActionId`, but only for tray menu actions (separate queue from the menubar).
- **`pumpTrayEvents()`** — Linux: D-Bus dispatch. macOS: short `NSApplication` event slice. Windows: `PeekMessage` / `DispatchMessage` for the tray HWND (call regularly from your loop).
- **`shutdownTray()`** — Remove the tray icon and release tray resources (independent of `shutdownDvuiMenu`).

Compile-time options are supplied through the generated module **`ztray_build_options`** (see this package’s `build.zig`).

## Building this package

From the `ztray/` directory:

```sh
zig fetch   # resolves lazy dependencies (dvui, wio) for examples
zig build
```

### Build option

| Flag | Meaning |
|------|---------|
| `-Dforce_dvui_menu=true` | Use DVUI’s immediate-mode menu inside your UI; you must call `drawMenuBar()` each frame. Default is **native** shell menus. |

Option names use **underscores** (Zig’s `zig build -D` convention), e.g. `-Dforce_dvui_menu=true`.

### Examples (installed by `zig build`)

| Artifact | Step | Notes |
|----------|------|--------|
| `ztray-dvui` | `zig build run-dvui` | DVUI window + ztray; native menu unless `-Dforce_dvui_menu=true`. |
| `ztray-wio-native` | `zig build run-wio` | [wio](https://github.com/ypsvlq/wio) window + native ztray menus only. |
| `ztray-wio-tray` | `zig build run-wio-tray` | wio window + native menubar + system tray (`windows_hwnd` = main window on Windows). |
| `ztray-tray-minimal` | `zig build run-tray` | Tray icon + context menu only (message-only HWND on Windows). |

On **Linux**, the wio and tray examples are linked **dynamically** where applicable (wio’s default Unix path expects dynamic linking when system integration is off).

## Layout

- `src/root.zig` — Public API and OS dispatch (menubar + tray).
- `src/types.zig` — Menu types and shortcuts.
- `src/macos_menu.m` / `src/macos_tray.m` — AppKit menubar and status item tray.
- `src/linux_dbus_menu.c` — Session D-Bus menubar + tray (DBusMenu + StatusNotifierItem when built on Linux).
- `src/dvui_fallback.zig` — DVUI menu implementation (compiled when `ztray_build_options.dvui_fallback` is true; this package’s `build.zig` keeps it enabled so examples and the forced menu path can share one module graph).
- `examples/` — Sample apps.

## License

Follow the license of the repository that contains this package (or add a dedicated license file here if you publish `ztray` standalone).
