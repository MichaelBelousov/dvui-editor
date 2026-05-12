const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dvui_fallback = b.option(bool, "dvui_fallback", "Compile DVUI immediate-mode menu fallback") orelse false;
    const force_dvui_menu = b.option(bool, "force_dvui_menu", "Use DVUI menu instead of native shell menus") orelse false;
    const wio_example = b.option(bool, "wio_example", "Build ztray + wio native shell menu example (lazy-fetched wio)") orelse false;

    if (wio_example and (dvui_fallback or force_dvui_menu)) {
        @panic("wio_example requires dvui_fallback=false and force_dvui_menu=false");
    }

    const zopts = b.addOptions();
    zopts.addOption(bool, "dvui_fallback", dvui_fallback);
    zopts.addOption(bool, "force_dvui_menu", force_dvui_menu);
    const zopts_mod = zopts.createModule();

    const ztray_mod = b.addModule("ztray", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ztray_mod.addImport("ztray_build_options", zopts_mod);

    if (dvui_fallback) {
        const dvui_dep = b.lazyDependency("dvui", .{
            .target = target,
            .optimize = optimize,
            .backend = .sdl3,
        }) orelse @panic("ztray DVUI fallback requires dependency 'dvui' (run: zig build --fetch)");
        ztray_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
        ztray_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
    }

    if (dvui_fallback and force_dvui_menu) {
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

        const example_exe = b.addExecutable(.{
            .name = "ztray-dvui-fallback",
            .root_module = example_mod,
        });
        b.installArtifact(example_exe);

        const run_dvui_cmd = b.addRunArtifact(example_exe);
        run_dvui_cmd.step.dependOn(b.getInstallStep());

        const run_dvui_fallback_step = b.step(
            "run-dvui-fallback",
            "Run the DVUI menu fallback sample (build with -Ddvui_fallback=true -Dforce_dvui_menu=true)",
        );
        run_dvui_fallback_step.dependOn(&run_dvui_cmd.step);
        if (b.args) |args| {
            run_dvui_cmd.addArgs(args);
        }
    }

    if (wio_example) {
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
        // wio Unix backend requires dynamic linkage when `system_integration` is off (default).
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
            "Run the ztray + wio native menu sample (build with -Dwio_example=true)",
        );
        run_wio_native_step.dependOn(&run_wio_cmd.step);
        if (b.args) |args| {
            run_wio_cmd.addArgs(args);
        }
    }
}
