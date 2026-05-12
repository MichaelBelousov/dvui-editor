# ztray

Cross-platform **application menu bar** for Zig: native shell menus on macOS (AppKit `NSMenu`), Windows (Win32 `HMENU` + `comctl32` subclassing), and Linux ([DBusMenu](https://github.com/canonical/dbusmenu) over D-Bus). Optional **in-app** menu bar using [DVUI](https://github.com/david-vanderson/dvui) when you compile with `force_dvui_menu` enabled (see below).

There is no runtime dependency on SDL or a window toolkit inside the core `ztray` sources; your app supplies a window handle on Windows when using native menus.

## Requirements

- **Zig** 0.16.0 or newer (see `build.zig.zon`).

## Using ztray in another project

Add a path (or fetched) dependency on this package, then **`addImport("ztray", dep.module("ztray"))`** on your app module. Use the same **`target`** and **`optimize`** as your executable, and set **`force_dvui_menu`** on the dependency if you want the in-app DVUI menu path instead of native shell menus.

This package’s **`build.zig`** attaches the native implementation (Objective-C on macOS, `comctl32` on Windows, D-Bus menu C or stub on Linux) to the **`ztray` module** itself, so you do **not** list `ztray`’s `.m` / `.c` files or `dbus-1` / `comctl32` in your own `build.zig` unless you have other reasons to.

On **Windows**, pass the top-level **`HWND`** as `?*anyopaque` to `installMainMenu` (for example from SDL’s `SDL_PROP_WINDOW_WIN32_HWND_POINTER`).

## API (summary)

- **`installMainMenu(allocator, menu_bar, hwnd)`** — Install menus. `hwnd` is required on Windows for native menus; ignored on macOS; unused on Linux for D-Bus registration.
- **`pollActionId()`** — Returns the last menu action id, or `null` (cleared on read).
- **`drawMenuBar()`** — Only when compile-time **`force_dvui_menu`** is set: call each frame from your DVUI tick to draw the in-app menu bar.
- **`shutdownDvuiMenu()`** — Release DVUI fallback menu storage when applicable.
- **`consumeCloseTabSuppression()`** — macOS helper for “close tab” style items that suppress the next window close.

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
| `ztray-wio` | `zig build run-wio` | [wio](https://github.com/ypsvlq/wio) window + native ztray menus only. |

On **Linux**, the wio example is linked **dynamically** (wio’s default Unix path expects dynamic linking when system integration is off).

## Layout

- `src/root.zig` — Public API and OS dispatch.
- `src/types.zig` — Menu types and shortcuts.
- `src/dvui_fallback.zig` — DVUI menu implementation (compiled when `ztray_build_options.dvui_fallback` is true; this package’s `build.zig` keeps it enabled so examples and the forced menu path can share one module graph).
- `examples/` — Sample apps.

## License

Follow the license of the repository that contains this package (or add a dedicated license file here if you publish `ztray` standalone).
