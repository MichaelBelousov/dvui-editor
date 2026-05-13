const std = @import("std");

/// Native menu implementation files; attached to the `ztray` module so consumers only `addImport("ztray", ...)`.
fn linkNativeMenu(ztray_mod: *std.Build.Module, b: *std.Build, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .macos => {
            ztray_mod.addCSourceFile(.{ .file = b.path("src/macos_menu.m") });
            ztray_mod.addCSourceFile(.{ .file = b.path("src/macos_tray.m") });
        },
        .windows => {
            ztray_mod.addCSourceFile(.{ .file = b.path("src/windows_tray_png.c") });
            ztray_mod.linkSystemLibrary("comctl32", .{});
            ztray_mod.linkSystemLibrary("shell32", .{});
            ztray_mod.linkSystemLibrary("gdi32", .{});
        },
        .linux => {
            const native_linux = b.graph.host.result.os.tag == .linux;
            if (native_linux) {
                ztray_mod.addCSourceFile(.{ .file = b.path("src/linux_dbus_menu.c") });
                ztray_mod.linkSystemLibrary("dbus-1", .{});
            } else {
                ztray_mod.addCSourceFile(.{ .file = b.path("src/linux_dbus_stub.c") });
            }
        },
        else => {},
    }
}

/// Options for the DVUI **sample** only (`force_dvui_menu` toggles native vs in-app menubar in that exe).
fn dvuiExampleOptsModule(b: *std.Build, force_dvui_menu: bool) *std.Build.Module {
    const zopts = b.addOptions();
    zopts.addOption(bool, "force_dvui_menu", force_dvui_menu);
    return zopts.createModule();
}

const DvuiImports = struct {
    dvui: *std.Build.Module,
    sdl: *std.Build.Module,
};

fn dvuiImportsFromDep(dep: *std.Build.Dependency) DvuiImports {
    return .{
        .dvui = dep.module("dvui_sdl3"),
        .sdl = dep.module("sdl3"),
    };
}

/// Core `ztray` module: no DVUI (or other UI toolkit) imports.
pub fn createZtrayModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const ztray_mod = b.addModule("ztray", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = if (target.result.os.tag == .windows) true else null,
    });
    linkNativeMenu(ztray_mod, b, target);
    return ztray_mod;
}

/// Optional macOS window chrome (transparent title bar + vibrancy). **Not** re-exported from the core `ztray` module; add as `addImport("zchrome", …)` separately from menu/tray.
pub fn createZchromeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const chrome_mod = b.addModule("zchrome", .{
        .root_source_file = b.path("src/chrome_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .macos) {
        chrome_mod.addCSourceFile(.{ .file = b.path("src/macos_chrome.m") });
        chrome_mod.linkFramework("AppKit", .{});
    }
    return chrome_mod;
}

/// Unified `ztray` module: same public API as `createZtrayModule` plus `ztray.dvui_menu` (DVUI in-app menubar). Pass as `addImport("ztray", ...)`.
pub fn createZtrayDvuiModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ztray_mod: *std.Build.Module,
    dvui_mod: *std.Build.Module,
    sdl_mod: *std.Build.Module,
) *std.Build.Module {
    const m = b.createModule(.{
        .root_source_file = b.path("src/ztray_with_dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    m.addImport("ztray_core", ztray_mod);
    m.addImport("dvui", dvui_mod);
    m.addImport("sdl-backend", sdl_mod);
    return m;
}

fn addDvuiExampleExe(
    b: *std.Build,
    ztray_unified_mod: *std.Build.Module,
    example_opts_mod: *std.Build.Module,
    d: DvuiImports,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe_name: []const u8,
) *std.Build.Step.Compile {
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/dvui_fallback/App.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("dvui", d.dvui);
    example_mod.addImport("sdl-backend", d.sdl);
    example_mod.addImport("ztray", ztray_unified_mod);
    example_mod.addImport("ztray_dvui_opts", example_opts_mod);

    return b.addExecutable(.{
        .name = exe_name,
        .root_module = example_mod,
    });
}

fn addWioNativeExe(
    b: *std.Build,
    ztray_mod: *std.Build.Module,
    wio_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe_name: []const u8,
) *std.Build.Step.Compile {
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/wio_native/App.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("wio", wio_mod);
    example_mod.addImport("ztray", ztray_mod);

    return b.addExecutable(.{
        .name = exe_name,
        .root_module = example_mod,
    });
}

fn addWioTrayExe(
    b: *std.Build,
    ztray_mod: *std.Build.Module,
    chrome_mod: *std.Build.Module,
    wio_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe_name: []const u8,
) *std.Build.Step.Compile {
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/wio_tray/App.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("wio", wio_mod);
    example_mod.addImport("ztray", ztray_mod);
    example_mod.addImport("zchrome", chrome_mod);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = example_mod,
    });
    if (target.result.os.tag == .macos) {
        exe.root_module.linkFramework("AppKit", .{});
    }
    return exe;
}

fn addWioMacosChromeExe(
    b: *std.Build,
    chrome_mod: *std.Build.Module,
    wio_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe_name: []const u8,
) *std.Build.Step.Compile {
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/wio_macos_chrome/App.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("wio", wio_mod);
    example_mod.addImport("zchrome", chrome_mod);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = example_mod,
    });
    if (target.result.os.tag == .macos) {
        exe.root_module.linkFramework("AppKit", .{});
    }
    return exe;
}

fn addTrayMinimalExe(
    b: *std.Build,
    ztray_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe_name: []const u8,
) *std.Build.Step.Compile {
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/tray_minimal/App.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("ztray", ztray_mod);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = example_mod,
    });
    if (target.result.os.tag == .macos) {
        exe.root_module.linkFramework("AppKit", .{});
    }
    return exe;
}

/// D-Bus is linked as a shared library only when building on Linux *for* Linux; cross builds use the stub without `-dynamic`.
fn linkLinuxDynamic(exe: *std.Build.Step.Compile, host_os: std.Target.Os.Tag, target_os: std.Target.Os.Tag) void {
    if (target_os == .linux and host_os == .linux) exe.linkage = .dynamic;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const force_dvui_menu = b.option(bool, "force_dvui_menu", "DVUI sample only: use in-app menu bar instead of native shell menus") orelse false;

    const ztray_mod = createZtrayModule(b, target, optimize);
    const chrome_mod = createZchromeModule(b, target, optimize);

    if (b.lazyDependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
    })) |dvui_dep| {
        const d = dvuiImportsFromDep(dvui_dep);
        const example_opts_mod = dvuiExampleOptsModule(b, force_dvui_menu);
        const ztray_unified_mod = createZtrayDvuiModule(b, target, optimize, ztray_mod, d.dvui, d.sdl);

        const example_exe = addDvuiExampleExe(b, ztray_unified_mod, example_opts_mod, d, target, optimize, "ztray-dvui");

        b.installArtifact(example_exe);

        const run_dvui_cmd = b.addRunArtifact(example_exe);
        run_dvui_cmd.step.dependOn(b.getInstallStep());

        const run_dvui_step = b.step(
            "run-dvui",
            "Run the DVUI + ztray sample (-Dforce_dvui_menu=true forces in-app menubar; Linux auto-fallback when AppMenu registrar is absent)",
        );
        run_dvui_step.dependOn(&run_dvui_cmd.step);
        if (b.args) |args| {
            run_dvui_cmd.addArgs(args);
        }
    }

    if (b.lazyDependency("wio", .{
        .target = target,
        .optimize = optimize,
    })) |wio_dep| {
        const wio_mod = wio_dep.module("wio");

        {
            const example_exe = addWioNativeExe(b, ztray_mod, wio_mod, target, optimize, "ztray-wio-native");
            linkLinuxDynamic(example_exe, b.graph.host.result.os.tag, target.result.os.tag);

            b.installArtifact(example_exe);

            const run_wio_cmd = b.addRunArtifact(example_exe);
            run_wio_cmd.step.dependOn(b.getInstallStep());

            const run_wio_native_step = b.step(
                "run-wio",
                "Run the ztray + wio native menu sample",
            );
            run_wio_native_step.dependOn(&run_wio_cmd.step);
            if (b.args) |args| {
                run_wio_cmd.addArgs(args);
            }
        }

        {
            const example_exe = addWioTrayExe(b, ztray_mod, chrome_mod, wio_mod, target, optimize, "ztray-wio-tray");
            linkLinuxDynamic(example_exe, b.graph.host.result.os.tag, target.result.os.tag);

            b.installArtifact(example_exe);

            const run_wio_tray_cmd = b.addRunArtifact(example_exe);
            run_wio_tray_cmd.step.dependOn(b.getInstallStep());

            const run_wio_tray_step = b.step(
                "run-wio-tray",
                "Run the ztray + wio sample with native menubar and system tray",
            );
            run_wio_tray_step.dependOn(&run_wio_tray_cmd.step);
            if (b.args) |args| {
                run_wio_tray_cmd.addArgs(args);
            }
        }

        if (target.result.os.tag == .macos) {
            const example_exe = addWioMacosChromeExe(b, chrome_mod, wio_mod, target, optimize, "ztray-wio-chrome");
            linkLinuxDynamic(example_exe, b.graph.host.result.os.tag, target.result.os.tag);

            b.installArtifact(example_exe);

            const run_wio_chrome_cmd = b.addRunArtifact(example_exe);
            run_wio_chrome_cmd.step.dependOn(b.getInstallStep());

            const run_wio_chrome_step = b.step(
                "run-wio-chrome",
                "Run wio + zchrome only (transparent title bar + vibrancy on macOS)",
            );
            run_wio_chrome_step.dependOn(&run_wio_chrome_cmd.step);
            if (b.args) |args| {
                run_wio_chrome_cmd.addArgs(args);
            }
        }
    }

    {
        const example_exe = addTrayMinimalExe(b, ztray_mod, target, optimize, "ztray-tray-minimal");
        linkLinuxDynamic(example_exe, b.graph.host.result.os.tag, target.result.os.tag);

        b.installArtifact(example_exe);

        const run_tray_cmd = b.addRunArtifact(example_exe);
        run_tray_cmd.step.dependOn(b.getInstallStep());

        const run_tray_step = b.step(
            "run-tray",
            "Run the tray-only ztray sample (message-only HWND on Windows)",
        );
        run_tray_step.dependOn(&run_tray_cmd.step);
        if (b.args) |args| {
            run_tray_cmd.addArgs(args);
        }
    }

    const types_test_mod = b.createModule(.{
        .root_source_file = b.path("src/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    const types_tests = b.addTest(.{
        .name = "ztray-types-tests",
        .root_module = types_test_mod,
    });
    const run_types_tests = b.addRunArtifact(types_tests);
    const test_step = b.step("test", "Run ztray unit tests (types and helpers)");
    test_step.dependOn(&run_types_tests.step);

    const ci_step = b.step(
        "ci",
        "Build all ztray examples for CI targets (Linux aarch64/x86_64, Windows x86_64; native macOS when host is macOS). Includes wio_tray.",
    );
    setupZtrayCi(b, ci_step, force_dvui_menu);
}

/// Cross-compiles every example executable for the same targets as the parent repo's `setupCi` (see root `build.zig`).
/// macOS is built only when the build graph host is macOS (Apple SDK; no Linux→macOS cross here).
fn setupZtrayCi(b: *std.Build, ci_step: *std.Build.Step, force_dvui_menu: bool) void {
    const optimize: std.builtin.OptimizeMode = .Debug;

    const cross_targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    };

    for (cross_targets) |q| {
        addZtrayCiExamplesForTarget(b, ci_step, b.resolveTargetQuery(q), optimize, force_dvui_menu);
    }

    if (b.graph.host.result.os.tag == .macos) {
        addZtrayCiExamplesForTarget(b, ci_step, b.graph.host, optimize, force_dvui_menu);
    }
}

fn addZtrayCiExamplesForTarget(
    b: *std.Build,
    ci_step: *std.Build.Step,
    resolved: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    force_dvui_menu: bool,
) void {
    const dvui_dep_opt = b.lazyDependency("dvui", .{
        .target = resolved,
        .optimize = optimize,
        .backend = .sdl3,
    });
    const wio_dep_opt = b.lazyDependency("wio", .{
        .target = resolved,
        .optimize = optimize,
    });
    const dvui_dep = dvui_dep_opt orelse return;
    const wio_dep = wio_dep_opt orelse return;

    const ztray_mod = createZtrayModule(b, resolved, optimize);
    const chrome_mod = createZchromeModule(b, resolved, optimize);
    const example_opts_mod = dvuiExampleOptsModule(b, force_dvui_menu);
    const d = dvuiImportsFromDep(dvui_dep);
    const ztray_unified_mod = createZtrayDvuiModule(b, resolved, optimize, ztray_mod, d.dvui, d.sdl);

    const os_tag = @tagName(resolved.result.os.tag);
    const arch_tag = @tagName(resolved.result.cpu.arch);

    const wio_mod = wio_dep.module("wio");

    ci_step.dependOn(&addDvuiExampleExe(
        b,
        ztray_unified_mod,
        example_opts_mod,
        d,
        resolved,
        optimize,
        b.fmt("ztray-dvui-{s}-{s}", .{ arch_tag, os_tag }),
    ).step);

    {
        const exe = addWioNativeExe(
            b,
            ztray_mod,
            wio_mod,
            resolved,
            optimize,
            b.fmt("ztray-wio-native-{s}-{s}", .{ arch_tag, os_tag }),
        );
        linkLinuxDynamic(exe, b.graph.host.result.os.tag, resolved.result.os.tag);
        ci_step.dependOn(&exe.step);
    }

    {
        const exe = addWioTrayExe(
            b,
            ztray_mod,
            chrome_mod,
            wio_mod,
            resolved,
            optimize,
            b.fmt("ztray-wio-tray-{s}-{s}", .{ arch_tag, os_tag }),
        );
        linkLinuxDynamic(exe, b.graph.host.result.os.tag, resolved.result.os.tag);
        ci_step.dependOn(&exe.step);
    }

    if (resolved.result.os.tag == .macos) {
        const exe = addWioMacosChromeExe(
            b,
            chrome_mod,
            wio_mod,
            resolved,
            optimize,
            b.fmt("ztray-wio-chrome-{s}-{s}", .{ arch_tag, os_tag }),
        );
        linkLinuxDynamic(exe, b.graph.host.result.os.tag, resolved.result.os.tag);
        ci_step.dependOn(&exe.step);
    }

    {
        const exe = addTrayMinimalExe(
            b,
            ztray_mod,
            resolved,
            optimize,
            b.fmt("ztray-tray-minimal-{s}-{s}", .{ arch_tag, os_tag }),
        );
        linkLinuxDynamic(exe, b.graph.host.result.os.tag, resolved.result.os.tag);
        ci_step.dependOn(&exe.step);
    }
}
