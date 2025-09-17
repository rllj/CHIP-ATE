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
    const is_wasm_build = b.option(
        bool,
        "wasm",
        "Whether to build as a wasm lib",
    ) orelse false;

    const chip_ate_mod = b.addModule("chip-ate-lib", .{
        .root_source_file = b.path("src/libchip8/cpu.zig"),
        .target = target,
        .optimize = optimize,
    });
    const options = b.addOptions();
    options.addOption(bool, "is_wasm", is_wasm_build);
    chip_ate_mod.addOptions("build_options", options);

    const chip_ate_lib = b.addLibrary(.{
        .name = "chip-ate",
        .root_module = chip_ate_mod,
    });

    const exe = exe: {
        if (!is_wasm_build) {
            const native_mod = b.createModule(.{
                .root_source_file = b.path("src/native/main.zig"),
                .target = target,
                .optimize = optimize,
            });

            const native_exe = b.addExecutable(.{
                .name = "chip-ate",
                .root_module = native_mod,
            });
            native_exe.bundle_ubsan_rt = true;

            const zglfw = b.dependency("zglfw", .{
                .x11 = display == .x11,
                .wayland = display == .wayland,
                .shared = shared,
            });
            native_exe.root_module.addImport("zglfw", zglfw.module("root"));
            if (target.result.os.tag != .emscripten) {
                native_exe.linkLibrary(zglfw.artifact("glfw"));
            }

            const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
                .api = .gl,
                .version = .@"4.1",
                .profile = .core,
                .extensions = &.{},
            });

            native_exe.root_module.addImport("gl", gl_bindings);

            break :exe native_exe;
        } else {
            const wasm = b.addLibrary(.{
                .name = "chip-ate-wasm",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/wasm/root.zig"),
                    .target = b.resolveTargetQuery(.{
                        .cpu_arch = .wasm32,
                        .os_tag = .emscripten,
                    }),
                    .optimize = optimize,
                }),
            });
            wasm.linkLibC();
            break :exe wasm;
        }
    };

    exe.root_module.addImport("chip-ate", chip_ate_lib.root_module);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
}
