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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const force_dvui_menu = b.option(bool, "force_dvui_menu", "Use in-app DVUI menu bar instead of native shell menus") orelse false;

    const ztray_dvui_fallback = true;

    const zopts = b.addOptions();
    zopts.addOption(bool, "dvui_fallback", ztray_dvui_fallback);
    zopts.addOption(bool, "force_dvui_menu", force_dvui_menu);
    const zopts_mod = zopts.createModule();

    const ztray_mod = b.addModule("ztray", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ztray_mod.addImport("ztray_build_options", zopts_mod);

    linkNativeMenu(ztray_mod, b, target);

    {
        const dvui_dep = b.lazyDependency("dvui", .{
            .target = target,
            .optimize = optimize,
            .backend = .sdl3,
        }) orelse @panic("ztray requires dependency 'dvui' (run: zig build --fetch)");
        ztray_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
        ztray_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
    }

    {
        const dvui_dep = b.dependency("dvui", .{
            .target = target,
            .optimize = optimize,
            .backend = .sdl3,
        });

        const example_mod = b.createModule(.{
            .root_source_file = b.path("examples/dvui_fallback/App.zig"),
            .target = target,
            .optimize = optimize,
        });
        example_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
        example_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
        example_mod.addImport("ztray", ztray_mod);
        example_mod.addImport("ztray_build_options", zopts_mod);

        const example_exe = b.addExecutable(.{
            .name = "ztray-dvui",
            .root_module = example_mod,
        });

        b.installArtifact(example_exe);

        const run_dvui_cmd = b.addRunArtifact(example_exe);
        run_dvui_cmd.step.dependOn(b.getInstallStep());

        const run_dvui_step = b.step(
            "run-dvui",
            "Run the DVUI + ztray sample (see README; use -Dforce_dvui_menu=true on the same zig build for in-app menu)",
        );
        run_dvui_step.dependOn(&run_dvui_cmd.step);
        if (b.args) |args| {
            run_dvui_cmd.addArgs(args);
        }
    }

    {
        const wio_dep = b.lazyDependency("wio", .{
            .target = target,
            .optimize = optimize,
        }) orelse @panic("ztray wio example requires dependency 'wio' (run: zig build --fetch)");

        const wio_mod = wio_dep.module("wio");

        const example_mod = b.createModule(.{
            .root_source_file = b.path("examples/wio_native/App.zig"),
            .target = target,
            .optimize = optimize,
        });
        example_mod.addImport("wio", wio_mod);
        example_mod.addImport("ztray", ztray_mod);

        const example_exe = b.addExecutable(.{
            .name = "ztray-wio-native",
            .root_module = example_mod,
        });
        if (target.result.os.tag == .linux) {
            example_exe.linkage = .dynamic;
        }

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
        const wio_dep = b.lazyDependency("wio", .{
            .target = target,
            .optimize = optimize,
        }) orelse @panic("ztray wio example requires dependency 'wio' (run: zig build --fetch)");

        const wio_mod = wio_dep.module("wio");

        const example_mod = b.createModule(.{
            .root_source_file = b.path("examples/wio_tray/App.zig"),
            .target = target,
            .optimize = optimize,
        });
        example_mod.addImport("wio", wio_mod);
        example_mod.addImport("ztray", ztray_mod);

        const example_exe = b.addExecutable(.{
            .name = "ztray-wio-tray",
            .root_module = example_mod,
        });
        if (target.result.os.tag == .linux) {
            example_exe.linkage = .dynamic;
        }
        if (target.result.os.tag == .macos) {
            example_exe.root_module.linkFramework("AppKit", .{});
        }

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

    {
        const example_mod = b.createModule(.{
            .root_source_file = b.path("examples/tray_minimal/App.zig"),
            .target = target,
            .optimize = optimize,
        });
        example_mod.addImport("ztray", ztray_mod);

        const example_exe = b.addExecutable(.{
            .name = "ztray-tray-minimal",
            .root_module = example_mod,
        });
        if (target.result.os.tag == .macos) {
            example_exe.root_module.linkFramework("AppKit", .{});
        }
        if (target.result.os.tag == .linux) {
            example_exe.linkage = .dynamic;
        }

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

    const ci_step = b.step(
        "ci",
        "Build all ztray examples for CI targets (Linux aarch64/x86_64, Windows x86_64; native macOS when host is macOS). Includes wio_tray.",
    );
    setupZtrayCi(b, ci_step, force_dvui_menu);
}

/// Cross-compiles every example executable for the same targets as the parent repo’s `setupCi` (see root `build.zig`).
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
    const zopts = b.addOptions();
    zopts.addOption(bool, "dvui_fallback", true);
    zopts.addOption(bool, "force_dvui_menu", force_dvui_menu);
    const zopts_mod = zopts.createModule();

    const ztray_mod = b.addModule("ztray", .{
        .root_source_file = b.path("src/root.zig"),
        .target = resolved,
        .optimize = optimize,
    });
    ztray_mod.addImport("ztray_build_options", zopts_mod);

    linkNativeMenu(ztray_mod, b, resolved);

    const dvui_dep = b.dependency("dvui", .{
        .target = resolved,
        .optimize = optimize,
        .backend = .sdl3,
    });
    ztray_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    ztray_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));

    const os_tag = @tagName(resolved.result.os.tag);
    const arch_tag = @tagName(resolved.result.cpu.arch);

    {
        const example_mod = b.createModule(.{
            .root_source_file = b.path("examples/dvui_fallback/App.zig"),
            .target = resolved,
            .optimize = optimize,
        });
        example_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
        example_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
        example_mod.addImport("ztray", ztray_mod);
        example_mod.addImport("ztray_build_options", zopts_mod);

        const exe = b.addExecutable(.{
            .name = b.fmt("ztray-dvui-{s}-{s}", .{ arch_tag, os_tag }),
            .root_module = example_mod,
        });
        ci_step.dependOn(&exe.step);
    }

    {
        const wio_dep = b.dependency("wio", .{
            .target = resolved,
            .optimize = optimize,
        });

        const example_mod = b.createModule(.{
            .root_source_file = b.path("examples/wio_native/App.zig"),
            .target = resolved,
            .optimize = optimize,
        });
        example_mod.addImport("wio", wio_dep.module("wio"));
        example_mod.addImport("ztray", ztray_mod);

        const exe = b.addExecutable(.{
            .name = b.fmt("ztray-wio-native-{s}-{s}", .{ arch_tag, os_tag }),
            .root_module = example_mod,
        });
        if (resolved.result.os.tag == .linux) {
            exe.linkage = .dynamic;
        }
        ci_step.dependOn(&exe.step);
    }

    {
        const wio_dep = b.dependency("wio", .{
            .target = resolved,
            .optimize = optimize,
        });

        const example_mod = b.createModule(.{
            .root_source_file = b.path("examples/wio_tray/App.zig"),
            .target = resolved,
            .optimize = optimize,
        });
        example_mod.addImport("wio", wio_dep.module("wio"));
        example_mod.addImport("ztray", ztray_mod);

        const exe = b.addExecutable(.{
            .name = b.fmt("ztray-wio-tray-{s}-{s}", .{ arch_tag, os_tag }),
            .root_module = example_mod,
        });
        if (resolved.result.os.tag == .linux) {
            exe.linkage = .dynamic;
        }
        if (resolved.result.os.tag == .macos) {
            exe.root_module.linkFramework("AppKit", .{});
        }
        ci_step.dependOn(&exe.step);
    }

    {
        const example_mod = b.createModule(.{
            .root_source_file = b.path("examples/tray_minimal/App.zig"),
            .target = resolved,
            .optimize = optimize,
        });
        example_mod.addImport("ztray", ztray_mod);

        const exe = b.addExecutable(.{
            .name = b.fmt("ztray-tray-minimal-{s}-{s}", .{ arch_tag, os_tag }),
            .root_module = example_mod,
        });
        if (resolved.result.os.tag == .macos) {
            exe.root_module.linkFramework("AppKit", .{});
        }
        if (resolved.result.os.tag == .linux) {
            exe.linkage = .dynamic;
        }
        ci_step.dependOn(&exe.step);
    }
}
