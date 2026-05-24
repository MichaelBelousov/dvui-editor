const std = @import("std");
const builtin = @import("builtin");

// dvui-editor's app build uses Zig 0.16+ APIs (transitively via dvui
// 0.5.0-dev / known_folders / nightwatch — e.g. `b.graph.environ_map`,
// `std.process.Child.StdIo.ignore`). Zig 0.15.2 still *comptime-analyzes*
// the bodies of every `b.lazyDependency(...)` call it sees, even with
// `.lazy = true` and even when the runtime branch never fires, which
// pulls those 0.16-only APIs into the analysis and fails with cryptic
// compile errors. So we gate the entire build body behind a comptime
// version check — on Zig < 0.16 the body is dead code and never gets
// analyzed. Consumers on 0.15.2 (e.g. graphl/ide) keep working because
// they only need `dep.path("src/widgets/TextEditWidget.zig")`.
const supports_app_build = builtin.zig_version.major > 0 or builtin.zig_version.minor >= 16;

const EditorBuildOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

/// Returns the editor module if all required deps are available; otherwise
/// null. All deps are pulled via `b.lazyDependency` so the editor can be
/// consumed purely for source paths (e.g. by the graphl IDE on Zig 0.15.2)
/// without triggering transitive 0.16-only fetches.
pub fn editorMod(b: *std.Build, opts: EditorBuildOptions) ?*std.Build.Module {
    // Same comptime gate as build() — on Zig < 0.16 the body is dead and
    // not analyzed, so the `b.lazyDependency` calls below don't pull in
    // the 0.16-only transitive build.zig files.
    if (comptime !supports_app_build) return null;

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
    // Declared unconditionally so consumers that always pass it (e.g.
    // graphl/ide on Zig 0.15.2) don't get an "unknown option" error.
    // Functionally a no-op now that the Zig-version gate below handles
    // the same case automatically.
    _ = b.option(
        bool,
        "paths_only",
        "Legacy: only useful when consuming this package for source paths. The Zig-version gate now handles this automatically.",
    );

    // Zig version gate — see top of file. On Zig < 0.16 the rest of this
    // body is dead code (not analyzed), which lets consumers like
    // graphl/ide resolve this package's source paths without triggering
    // compile of the 0.16-only transitive deps.
    if (comptime !supports_app_build) return;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    // Same comptime gate as build() / editorMod().
    if (comptime !supports_app_build) return;

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
