const std = @import("std");
const heap = std.heap;
const mem = std.mem;

const CHIP8 = @import("cpu.zig").CHIP8;
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

    var cpu = try CHIP8.init(rom, allocator);
    defer cpu.deinit(allocator);

    const window = try Window.init();
    defer window.deinit();
    window.attach_cpu(&cpu);

    while (!window.should_close()) {
        cpu.cycle();
        window.draw(cpu.display);
    }
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
