const std = @import("std");

const chip_ate = @import("chip-ate");
const CPU = chip_ate.CHIP8;

const SCREEN_HEIGHT = chip_ate.SCREEN_HEIGHT;
const SCREEN_WIDTH = chip_ate.SCREEN_WIDTH;
const PIXEL_COUNT = chip_ate.PIXEL_COUNT;

var cpu: CPU = undefined;

var fba: std.heap.FixedBufferAllocator = undefined;

export fn init(
    rom: [*]const u8,
    rom_size: usize,
    mappings: [*]u32,
    memory_buffer: [*]u8,
    buffer_size: usize,
) void {
    fba = std.heap.FixedBufferAllocator.init(memory_buffer[0..buffer_size]);

    cpu = CPU.init(
        rom[0..rom_size],
        @as(*CPU.Input.Mappings, @ptrCast(@alignCast(mappings))).*,
        fba.allocator(),
    ) catch unreachable;
}

export fn deinit() void {
    cpu.deinit(fba.allocator());
}

export fn cycle() void {
    CPU.cycle(&cpu);
}

export fn get_pixels() *[PIXEL_COUNT]u8 {
    return @ptrCast(cpu.display);
}
