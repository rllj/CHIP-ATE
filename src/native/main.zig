const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const glfw = @import("zglfw");

const CHIP8 = @import("chip-ate").CHIP8;
const Window = @import("window.zig").Window;

pub const SCREEN_WIDTH = 64;
pub const SCREEN_HEIGHT = 32;
pub const PIXEL_COUNT = 64 * 32;

pub fn main() !void {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer _ = arena.reset(.free_all);
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = std.fs.File.stdout();
    var stdout_writer: std.fs.File.Writer = .init(stdout, &.{});

    if (args.len != 2) {
        try help(&stdout_writer.interface);
        std.process.exit(1);
    }

    const rom = try read_file_from_path(allocator, args[1]);
    defer allocator.free(rom);

    var cpu = try CHIP8.init(rom, .{
        .@"1" = glfw.Key.one,
        .@"2" = glfw.Key.two,
        .@"3" = glfw.Key.three,
        .C = glfw.Key.four,
        .@"4" = glfw.Key.q,
        .@"5" = glfw.Key.w,
        .@"6" = glfw.Key.e,
        .D = glfw.Key.r,
        .@"7" = glfw.Key.a,
        .@"8" = glfw.Key.s,
        .@"9" = glfw.Key.d,
        .E = glfw.Key.f,
        .A = glfw.Key.z,
        .@"0" = glfw.Key.x,
        .B = glfw.Key.c,
        .F = glfw.Key.v,
    }, allocator);
    defer cpu.deinit(allocator);

    const window = try Window.init();
    defer window.deinit();

    glfw.setWindowUserPointer(window.glfw_window, &cpu);
    glfw.setKeyCallback(window.glfw_window, on_key_action);

    while (!window.should_close()) {
        cpu.cycle();
        window.draw(cpu.display);
    }
}

fn on_key_action(
    window: *glfw.Window,
    key: glfw.Key,
    _: c_int,
    action: glfw.Action,
    _: glfw.Mods,
) void {
    const cpu = window.getUserPointer(CHIP8) orelse return error.GLFWWindowError;
    const chip8_
    cpu.input.on_key_event(@as(CHIP8.Input.Key, key));
}

pub fn help(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\Usage: chip-ate [options] rom_path
        \\  options:
        \\    -h, --help       Print this message and exit
        \\
    );
}

// TODO: improve
pub fn read_file_from_path(allocator: mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_len = try file.getEndPos();
    const text = try allocator.alloc(u8, file_len);

    var buffer: [4096]u8 = undefined;
    var reader: std.fs.File.Reader = .init(file, &buffer);
    _ = try reader.interface.readSliceShort(text);
    return text;
}
