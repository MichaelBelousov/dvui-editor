const std = @import("std");

const EditorBuildOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

/// Returns the editor module if all required deps are available; otherwise
/// null. All deps are pulled via `b.lazyDependency` so the editor can be
/// consumed purely for source paths (e.g. by the graphl IDE on Zig 0.15.2)
/// without triggering transitive 0.16-only fetches.
pub fn editorMod(b: *std.Build, opts: EditorBuildOptions) ?*std.Build.Module {
    const dvui_dep = b.lazyDependency("dvui", .{
        .target = opts.target,
        .optimize = opts.optimize,
        .backend = .sdl3,
    }) orelse return null;
    const known_folders_dep = b.lazyDependency("known_folders", .{
        .target = opts.target,
        .optimize = opts.optimize,
    }) orelse return null;
    const nightwatch_dep = b.lazyDependency("nightwatch", .{
        .target = opts.target,
        .optimize = opts.optimize,
    }) orelse return null;

    const mod = b.createModule(.{
        .root_source_file = b.path("src/App.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
    mod.addImport("known-folders", known_folders_dep.module("known-folders"));
    mod.addImport("nightwatch", nightwatch_dep.module("nightwatch"));

    if (b.lazyDependency("icons", .{ .target = opts.target, .optimize = opts.optimize })) |dep| {
        mod.addImport("icons", dep.module("icons"));
    }

    if (opts.target.result.os.tag == .macos) {
        mod.addCSourceFile(.{ .file = std.Build.path(b, "src/macos_native.m") });
    } else if (opts.target.result.os.tag == .windows) {
        if (b.lazyDependency("win32", .{})) |dep| {
            mod.addImport("win32", dep.module("win32"));
        }
        mod.linkSystemLibrary("comctl32", .{});
    }
    return mod;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // When set, this build.zig skips every `b.lazyDependency(...)` call so
    // it can be evaluated by consumers (e.g. the graphl IDE on Zig 0.15.2)
    // who only want `dep.path("src/...")` and don't have the 0.16-only
    // `dvui` / `known_folders` / `nightwatch` graphs in a buildable state.
    //
    // Marking the deps `.lazy = true` in build.zig.zon isn't enough on its
    // own: once those deps have ever been fetched into the global cache,
    // `b.lazyDependency` returns the *cached* instance and runs its
    // build.zig, which is exactly the failure we're avoiding.
    const paths_only = b.option(
        bool,
        "paths_only",
        "Don't fetch/build any transitive deps. Only useful when consuming this package for source paths.",
    ) orelse false;

    std.debug.print("[dvui-editor build.zig] paths_only={}\n", .{paths_only});
    if (paths_only) return;

    // Reusable text edit widget exposed as a standalone module. Uses a
    // *lazy* dvui dep so consumers without dvui fetched yet can still
    // resolve this build.zig successfully.
    const text_edit_widget_mod = b.addModule("text_edit_widget", .{
        .root_source_file = b.path("src/widgets/TextEditWidget.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (b.lazyDependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
    })) |dvui_dep_for_widgets| {
        text_edit_widget_mod.addImport("dvui", dvui_dep_for_widgets.module("dvui_sdl3"));
    }

    const app_mod = editorMod(b, .{ .target = target, .optimize = optimize }) orelse return;

    const exe = b.addExecutable(.{
        .name = "dvui-editor",
        .root_module = app_mod,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{ .root_module = app_mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const ci_step = b.step("ci", "Run CI");
    setupCi(b, ci_step);
}

pub fn setupCi(b: *std.Build, step: *std.Build.Step) void {
    const targets: []const std.Target.Query = &.{
        // macOS cross-compilation requires the Apple SDK; build natively instead.
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
    };

    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        const app_mod = editorMod(b, .{ .target = target, .optimize = .Debug }) orelse continue;
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
