const std = @import("std");

const chip_ate = @import("chip-ate");
const CPU = chip_ate.CHIP8;

const SCREEN_HEIGHT = chip_ate.SCREEN_HEIGHT;
const SCREEN_WIDTH = chip_ate.SCREEN_WIDTH;
const PIXEL_COUNT = chip_ate.PIXEL_COUNT;

var cpu: CPU = undefined;

export fn init(rom: [*]const u8, rom_size: usize, mappings: [*]const u32) void {
    cpu = CPU.init(rom[0..rom_size], mappings, std.heap.page_allocator) catch unreachable;
}

export fn deinit() void {
    cpu.deinit(std.heap.page_allocator);
}

export fn cycle() void {
    CPU.cycle(&cpu);
}

export fn get_pixels() *[PIXEL_COUNT]u8 {
    return @ptrCast(cpu.display);
}
