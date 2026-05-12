const std = @import("std");

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

        switch (target.result.os.tag) {
            .macos => {
                example_exe.root_module.addCSourceFile(.{ .file = b.path("src/macos_menu.m") });
            },
            .windows => {
                example_exe.root_module.linkSystemLibrary("comctl32", .{});
            },
            .linux => {
                const native_linux = b.graph.host.result.os.tag == .linux;
                if (native_linux) {
                    example_exe.root_module.addCSourceFile(.{ .file = b.path("src/linux_dbus_menu.c") });
                    example_exe.root_module.linkSystemLibrary("dbus-1", .{});
                } else {
                    example_exe.root_module.addCSourceFile(.{ .file = b.path("src/linux_dbus_stub.c") });
                }
            },
            else => {},
        }

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

        switch (target.result.os.tag) {
            .macos => {
                example_exe.root_module.addCSourceFile(.{ .file = b.path("src/macos_menu.m") });
            },
            .windows => {
                example_exe.root_module.linkSystemLibrary("comctl32", .{});
            },
            .linux => {
                const native_linux = b.graph.host.result.os.tag == .linux;
                if (native_linux) {
                    example_exe.root_module.addCSourceFile(.{ .file = b.path("src/linux_dbus_menu.c") });
                    example_exe.root_module.linkSystemLibrary("dbus-1", .{});
                } else {
                    example_exe.root_module.addCSourceFile(.{ .file = b.path("src/linux_dbus_stub.c") });
                }
            },
            else => {},
        }

        b.installArtifact(example_exe);

        const run_wio_cmd = b.addRunArtifact(example_exe);
        run_wio_cmd.step.dependOn(b.getInstallStep());

        const run_wio_native_step = b.step(
            "run-wio-native",
            "Run the ztray + wio native menu sample",
        );
        run_wio_native_step.dependOn(&run_wio_cmd.step);
        if (b.args) |args| {
            run_wio_cmd.addArgs(args);
        }
    }
}
