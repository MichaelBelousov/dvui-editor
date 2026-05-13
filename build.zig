const std = @import("std");

const ztray = @import("ztray");

const EditorBuildOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// When set, passed to `createZwindowModule`. The root `build()` passes the parsed `-Dzwindow_unix_backends` here for the main app; CI passes explicit `ztray.ZwindowUnixBackends` values.
    zwindow_unix_backends: ztray.ZwindowUnixBackends = .both,
};

pub fn editorMod(b: *std.Build, opts: EditorBuildOptions) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/App.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    const dvui_dep = b.dependency("dvui", .{ .target = opts.target, .optimize = opts.optimize, .backend = .sdl3 });

    // Or use a prelinked one:
    mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    mod.addImport("sdl-backend", dvui_dep.module("sdl3")); // for zls;

    const known_folders = b.dependency("known_folders", .{
        .target = opts.target,
        .optimize = opts.optimize,
    }).module("known-folders");
    mod.addImport("known-folders", known_folders);

    const nightwatch = b.dependency("nightwatch", .{
        .target = opts.target,
        .optimize = opts.optimize,
    }).module("nightwatch");
    mod.addImport("nightwatch", nightwatch);

    if (b.lazyDependency("icons", .{ .target = opts.target, .optimize = opts.optimize })) |dep| {
        mod.addImport("icons", dep.module("icons"));
    }

    const ztray_dep = b.dependency("ztray", .{
        .target = opts.target,
        .optimize = opts.optimize,
    });
    const zwb = opts.zwindow_unix_backends;
    const ztray_mod = ztray.createZtrayModule(ztray_dep.builder, opts.target, opts.optimize);
    const zwindow_mod = ztray.createZwindowModule(ztray_dep.builder, opts.target, opts.optimize, zwb);
    const ztray_dvui_mod = ztray.createZtrayDvuiModule(
        ztray_dep.builder,
        opts.target,
        opts.optimize,
        ztray_mod,
        dvui_dep.module("dvui_sdl3"),
        dvui_dep.module("sdl3"),
    );
    mod.addImport("ztray", ztray_dvui_mod);
    mod.addImport("zwindow", zwindow_mod);

    const cmark_gfm = b.dependency("cmark_gfm", .{
        .target = opts.target,
        .optimize = opts.optimize,
    });
    mod.linkLibrary(cmark_gfm.artifact("cmark-gfm"));
    mod.linkLibrary(cmark_gfm.artifact("cmark-gfm-extensions"));
    mod.addIncludePath(cmark_gfm.path("src"));
    mod.addIncludePath(cmark_gfm.path("extensions"));
    mod.addIncludePath(b.path("src/md"));

    // const assetpack = @import("assetpack");
    // const assets_module = assetpack.pack(b, b.path("assets"), .{});
    // exe.root_module.addImport("assets", assets_module);
    return mod;
}

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    // const mod = b.addModule("dvui_editor", .{
    //     // The root source file is the "entry point" of this module. Users of
    //     // this module will only be able to access public declarations contained
    //     // in this file, which means that if you have declarations that you
    //     // intend to expose to consumers that were defined in other files part
    //     // of this module, you will have to make sure to re-export them from
    //     // the root file.
    //     .root_source_file = b.path("src/root.zig"),
    //     // Later on we'll use this module as the root module of a test executable
    //     // which requires us to specify a target.
    //     .target = target,
    // });

    const zwindow_unix_backends = ztray.ZwindowUnixBackends.parse(b.option(
        []const u8,
        "zwindow_unix_backends",
        "Comma-separated zwindow Linux backends: x11, wayland (default: x11,wayland)",
    ) orelse "x11,wayland");

    const app_mod = editorMod(b, .{
        .target = target,
        .optimize = optimize,
        .zwindow_unix_backends = zwindow_unix_backends,
    });

    const exe = b.addExecutable(.{
        .name = "dvui-editor",
        .root_module = app_mod,
    });
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = app_mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const ci_step = b.step("ci", "Run CI");
    setupCi(b, ci_step, zwindow_unix_backends);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
pub fn setupCi(b: *std.Build, step: *std.Build.Step, zwindow_unix_backends: ztray.ZwindowUnixBackends) void {
    const targets: []const std.Target.Query = &.{
        // macOS cross-compilation requires the Apple SDK; build natively instead.
        // .{ .cpu_arch = .aarch64, .os_tag = .macos },
        // .{ .cpu_arch = .x86_64,  .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        // .{ .cpu_arch = .aarch64, .os_tag = .windows },
    };

    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        if (t.os_tag.? == .linux) {
            inline for (std.enums.values(ztray.ZwindowUnixBackends)) |zwb| {
                const app_mod = editorMod(b, .{
                    .target = target,
                    .optimize = .Debug,
                    .zwindow_unix_backends = zwb,
                });
                const exe = b.addExecutable(.{
                    .name = b.fmt("dvui-editor-{s}-{s}-zw-{s}", .{
                        @tagName(t.cpu_arch.?),
                        @tagName(t.os_tag.?),
                        @tagName(zwb),
                    }),
                    .root_module = app_mod,
                });
                step.dependOn(&exe.step);
            }
        } else {
            const app_mod = editorMod(b, .{
                .target = target,
                .optimize = .Debug,
                .zwindow_unix_backends = zwindow_unix_backends,
            });
            const exe = b.addExecutable(.{
                .name = b.fmt("dvui-editor-{s}-{s}", .{
                    @tagName(t.cpu_arch.?),
                    @tagName(t.os_tag.?),
                }),
                .root_module = app_mod,
            });
            step.dependOn(&exe.step);
        }
    }
}
