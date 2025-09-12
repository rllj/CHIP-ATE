const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const Display = enum { x11, wayland };
    const display = b.option(
        Display,
        "display-server",
        "Whether to use X11 or Wayland (defaults to Wayland)",
    ) orelse .wayland;
    const shared = b.option(
        bool,
        "glfw-shared",
        "Whether to use glfw as a shared library",
    ) orelse false;

    const chip_ate_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "chip-ate",
        .root_module = chip_ate_mod,
    });
    exe.bundle_ubsan_rt = true;

    const zglfw = b.dependency("zglfw", .{
        .x11 = display == .x11,
        .wayland = display == .wayland,
        .shared = shared,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    if (target.result.os.tag != .emscripten) {
        exe.linkLibrary(zglfw.artifact("glfw"));
    }

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        .extensions = &.{},
    });

    exe.root_module.addImport("gl", gl_bindings);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    const tests = b.addTest(.{
        .root_module = chip_ate_mod,
    });

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
