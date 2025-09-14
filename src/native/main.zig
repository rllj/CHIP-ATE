const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const assert = std.debug.assert;
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
        .@"1" = @intFromEnum(glfw.Key.one),
        .@"2" = @intFromEnum(glfw.Key.two),
        .@"3" = @intFromEnum(glfw.Key.three),
        .C = @intFromEnum(glfw.Key.four),
        .@"4" = @intFromEnum(glfw.Key.q),
        .@"5" = @intFromEnum(glfw.Key.w),
        .@"6" = @intFromEnum(glfw.Key.e),
        .D = @intFromEnum(glfw.Key.r),
        .@"7" = @intFromEnum(glfw.Key.a),
        .@"8" = @intFromEnum(glfw.Key.s),
        .@"9" = @intFromEnum(glfw.Key.d),
        .E = @intFromEnum(glfw.Key.f),
        .A = @intFromEnum(glfw.Key.z),
        .@"0" = @intFromEnum(glfw.Key.x),
        .B = @intFromEnum(glfw.Key.c),
        .F = @intFromEnum(glfw.Key.v),
    }, allocator);
    defer cpu.deinit(allocator);

    const window = try Window.init();
    defer window.deinit();

    glfw.setWindowUserPointer(window.glfw_window, &cpu);
    _ = glfw.setKeyCallback(window.glfw_window, on_key_action);

    while (!window.glfw_window.shouldClose()) {
        cpu.cycle();
        window.draw(cpu.display);
    }
}

fn on_key_action(
    window: *glfw.Window,
    key: glfw.Key,
    _: c_int,
    glfw_action: glfw.Action,
    _: glfw.Mods,
) callconv(.c) void {
    const cpu = window.getUserPointer(CHIP8) orelse unreachable;
    const action: CHIP8.Input.Action = if (glfw_action == .release) .release else .press;
    cpu.input.on_key_event(glfw_key_to_u32(key), action);
}

pub fn glfw_key_to_u32(glfw_key: glfw.Key) u32 {
    comptime assert(@sizeOf(glfw.Key) <= @sizeOf(u32));
    return @bitCast(@intFromEnum(glfw_key));
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
