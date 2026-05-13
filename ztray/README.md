# ztray

Cross-platform **menu bar** and **system tray** for Zig.

| Platform | Menu bar | Tray |
|----------|----------|------|
| macOS    | AppKit `NSMenu` | `NSStatusItem` |
| Windows  | Win32 `HMENU` + `comctl32` | `Shell_NotifyIcon` |
| Linux    | DBusMenu over D-Bus | StatusNotifierItem |

An optional **in-app** DVUI menu bar is available via `ztray.dvui_menu` when you use `createZtrayDvuiModule`. The core module never imports DVUI. Tray is always native.

---

## Requirements

- Zig **0.16.0** or newer

---

## Setup

Add a path (or fetched) dependency, then `addImport("ztray", …)` with matching `target` / `optimize`.

### Native menus / tray only

```zig
const ztray_mod = createZtrayModule(b, target, optimize);
exe.addImport("ztray", ztray_mod);
```

### Native + DVUI in-app menu bar

```zig
const ztray_mod  = createZtrayModule(b, target, optimize);
const ztray_dvui = createZtrayDvuiModule(b, target, optimize, ztray_mod, dvui_mod, sdl_mod);
exe.addImport("ztray", ztray_dvui);
```

Use `ztray.dvui_menu` for in-app calls. Use `ztray.installMainMenuForSdlDvuiWindow` to get the native `HWND` from SDL automatically on Windows.

### Optional window frame chrome (`zwindow`)

```zig
const zwindow_mod = createZwindowModule(…);
exe.addImport("zwindow", zwindow_mod);
```

| OS | Call | Notes |
|----|------|-------|
| macOS | `zwindow.setFrameChrome(ns_window, policy)` | `.tray_compatible` / `.full_vibrancy` |
| Windows | `zwindow.setFrameChrome(hwnd, policy)` | |
| Linux | `zwindow.setFrameChrome(linux_frame_target, policy)` | X11: theme hint + opacity + KDE blur region; Wayland: clears opaque region, attaches KWin blur on `.full_vibrancy` |

Pass `-Dzwindow_unix_backends=x11,wayland` (default: both). Wayland support `dlopen`s `libwayland-client.so.0` at runtime — no static link needed.

`zwindow` is **not** re-exported from the core `ztray` module.

---

## Build

```sh
zig fetch        # resolve lazy deps (dvui, wio) for examples
zig build
zig build test   # unit tests
zig build ci     # cross-build examples (Linux: x11 / wayland / both × arches)
```

### Build flags

| Flag | Meaning |
|------|---------|
| `-Dforce_dvui_menu=true` | Force DVUI in-app menu bar in the `ztray-dvui` sample |
| `-Dzwindow_unix_backends` | Comma list: `x11`, `wayland` (default: `x11,wayland`) |

### Examples

| Step | Binary | Notes |
|------|--------|-------|
| `zig build run-tray` | `ztray-tray-minimal` | Tray icon + context menu only. |
| `zig build run-dvui` | `ztray-dvui` | DVUI window + ztray. Native menu by default; `-Dforce_dvui_menu=true` for in-app. |
| `zig build run-wio` | `ztray-wio-menu` | [wio](https://github.com/ypsvlq/wio) window + native menus only. |
| `zig build run-wio-window` | `ztray-wio-window` | wio + `zwindow.setFrameChrome(.full_vibrancy)`. |
| `zig build run-wio-tray` | `ztray-wio-tray` | wio + native menu bar + tray + `zwindow.setFrameChrome`. |

On Linux, wio and tray examples link dynamically where applicable.
