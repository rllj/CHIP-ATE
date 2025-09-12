const std = @import("std");
const glfw = @import("zglfw");
const t = std.testing;

const Random = std.Random;

const assert = std.debug.assert;

const log = std.log.scoped(.cpu);

const SCREEN_WIDTH = @import("main.zig").SCREEN_WIDTH;
const SCREEN_HEIGHT = @import("main.zig").SCREEN_HEIGHT;
const PIXEL_COUNT = @import("main.zig").PIXEL_COUNT;

// Font taken directly from
// https://tobiasvl.github.io/blog/write-a-chip-8-emulator/
const FONT = [80]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

pub const CHIP8 = struct {
    memory: Memory,
    stack: Stack, // Cheat a little and have the stack outside of RAM
    registers: Registers,
    // Timers
    delay: Countdown,
    sound: Countdown,
    time_to_next_frame: Countdown, // Draws a frame and is reset when it reaches 0
    display: *[SCREEN_HEIGHT][SCREEN_WIDTH]u8,
    input: Input,
    timer: std.time.Timer,

    pub fn init(rom: []const u8, allocator: std.mem.Allocator) !CHIP8 {
        comptime assert(@sizeOf(Memory) == 0x1000);
        var memory: Memory = .{ .sections = .{} };
        @memcpy(memory.sections.ram[0..rom.len], rom);
        const pc = 0x0200;

        const timer = std.time.Timer.start() catch unreachable;

        const pixels = try allocator.create([SCREEN_HEIGHT][SCREEN_WIDTH]u8);
        @memset(@as(*[SCREEN_HEIGHT * SCREEN_WIDTH]u8, @ptrCast(pixels)), 0);

        return .{
            .memory = memory,
            .stack = .{},
            .registers = .{ .pc = pc },
            .delay = Countdown.from_u8_seconds(0),
            .sound = Countdown.from_u8_seconds(0),
            .time_to_next_frame = .{ .ns = 1_000_000_000 / 60 },
            .input = .{ // TODO: Config
                .mappings = .{
                    // zig fmt: off
                .@"1" = glfw.Key.one,
                .@"2" = glfw.Key.two,
                .@"3" = glfw.Key.three,
                .C    = glfw.Key.four,
                .@"4" = glfw.Key.q,
                .@"5" = glfw.Key.w,
                .@"6" = glfw.Key.e,
                .D    = glfw.Key.r,
                .@"7" = glfw.Key.a,
                .@"8" = glfw.Key.s,
                .@"9" = glfw.Key.d,
                .E    = glfw.Key.f,
                .A    = glfw.Key.z,
                .@"0" = glfw.Key.x,
                .B    = glfw.Key.c,
                .F    = glfw.Key.v,
                // zig fmt: on
                },
            },
            .display = pixels,
            .timer = timer,
        };
    }

    pub fn deinit(self: CHIP8, allocator: std.mem.Allocator) void {
        allocator.free(@as(*[PIXEL_COUNT]u8, @ptrCast(self.display)));
    }

    pub fn cycle(self: *CHIP8) void {
        const pc = &self.registers.pc;
        const inst_upper: u16 = self.memory.contiguous[pc.*];
        const inst_lower: u16 = self.memory.contiguous[pc.* + 1];
        const inst = inst_upper << 8 | inst_lower;
        pc.* += 2;

        // Decremented 60 times per second
        const time = self.timer.lap();
        self.delay.ns -|= time * 60;
        self.sound.ns -|= time * 60;
        if (self.time_to_next_frame.ns == 0) self.time_to_next_frame.ns = 1_000_000_000 / 60;
        self.time_to_next_frame.ns -|= time;
        self.execute(inst);
    }

    pub fn execute(self: *CHIP8, inst_bits: u16) void {
        const inst: Instruction = @bitCast(inst_bits);

        log.debug("inst: 0x{x}", .{inst_bits});

        switch (inst_bits) {
            0x0000...0x0FFF => {
                switch (inst_bits) {
                    0x00E0 => { // Clear screen
                        @memset(@as(*[PIXEL_COUNT]u8, @ptrCast(self.display)), 0);
                    },
                    0x00EE => self.registers.pc = self.stack.pop(), // Return
                    else => invalid_inst(inst_bits),
                }
            },
            0x1000...0x1FFF => { // Jump
                const nnn = inst.nibbles.nnn.nnn;
                self.registers.pc = nnn;
            },
            0x2000...0x2FFF => { // Call
                self.stack.push(self.registers.pc);
                self.registers.pc = inst.nibbles.nnn.nnn;
            },
            0x3000...0x3FFF => { // Skip if VX == NN
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                if (self.registers.v[x] == nn) {
                    self.registers.pc += 2;
                }
            },
            0x4000...0x4FFF => { // Skip if VX != NN
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                if (self.registers.v[x] != nn) {
                    self.registers.pc += 2;
                }
            },
            0x5000...0x5FFF => skip: { // Skip if VX == VY
                const x = inst.nibbles.xyn.x;
                const y = inst.nibbles.xyn.y;
                const n = inst.nibbles.xyn.n;
                if (n != 0) break :skip;
                assert(inst_bits & 0xF == n);
                if (self.registers.v[x] == self.registers.v[y]) {
                    self.registers.pc += 2;
                }
            },
            0x6000...0x6FFF => { // Set VX to NN
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                self.registers.v[x] = nn;
            },
            0x7000...0x7FFF => { // Add NN to VX
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                assert(inst_bits & 0xFF == nn);
                self.registers.v[x] +%= nn;
            },
            0x8000...0x8FFF => {
                const x = inst.nibbles.xyo.x;
                const y = inst.nibbles.xyo.y;
                const al = inst.nibbles.xyo.al;
                const vx = &self.registers.v[x];
                const vy = &self.registers.v[y];
                const vf = &self.registers.v[0xF];

                vf.* = 0;

                switch (al) {
                    0x0 => vx.* = vy.*,
                    0x1 => vx.* |= vy.*,
                    0x2 => vx.* &= vy.*,
                    0x3 => vx.* ^= vy.*,
                    0x4 => {
                        vx.*, vf.* = @addWithOverflow(vx.*, vy.*);
                    },
                    0x5 => {
                        vx.*, vf.* = @subWithOverflow(vx.*, vy.*);
                        vf.* ^= 1;
                    },
                    0x7 => {
                        vx.*, vf.* = @subWithOverflow(vy.*, vx.*);
                        vf.* ^= 1;
                    },
                    0x6 => {
                        const overflow = vy.* & 1;
                        vx.* = vy.* >> 1;
                        vf.* = overflow;
                    },
                    0xE => {
                        vx.*, vf.* = @shlWithOverflow(vy.*, 1);
                    },
                    else => invalid_inst(inst_bits),
                }
            },
            0x9000...0x9FFF => skip: { // Skip if VX != VY
                if (inst.nibbles.xyn.n != 0) break :skip;
                const x = inst.nibbles.xyn.x;
                const y = inst.nibbles.xyn.y;
                if (self.registers.v[x] != self.registers.v[y]) {
                    self.registers.pc += 2;
                }
            },
            0xA000...0xAFFF => { // Set index register to NNN
                self.registers.i = inst.nibbles.nnn.nnn;
            },
            0xB000...0xBFFF => self.registers.pc = inst.nibbles.nnn.nnn + self.registers.v[0],
            0xC000...0xCFFF => { // Random number and mask
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                var prng = Random.DefaultPrng.init(123);
                var rand: u8 = @truncate(prng.next());
                rand &= nn;
                self.registers.v[x] = rand;
            },
            0xD000...0xDFFF => { // Draw
                const x = inst.nibbles.xyn.x;
                const y = inst.nibbles.xyn.y;
                const n = inst.nibbles.xyn.n;
                assert(inst_bits & 0xF == n);

                const start_x: u16 = self.registers.v[x] % SCREEN_WIDTH;
                const start_y: u16 = self.registers.v[y] % SCREEN_HEIGHT;

                self.registers.v[0xF] = 0;

                for (0..n) |byte| {
                    const y_coord = start_y + byte;
                    if (y_coord > 31) break;
                    const sprite = self.memory.contiguous[self.registers.i + byte];
                    for (0..8) |i| {
                        const x_coord = start_x + i;
                        if (x_coord > 63) break;

                        const pixel = (sprite >> @truncate(7 - i)) & 1;
                        const mask: u8 = pixel * 255;

                        const dest_pixel = &self.display[31 - y_coord][x_coord];

                        self.registers.v[0xF] = dest_pixel.*;
                        dest_pixel.* ^= mask;
                        self.registers.v[0xF] ^= mask;
                        self.registers.v[0xF] &= 1;
                    }
                }
                std.Thread.sleep(self.time_to_next_frame.ns);
                self.time_to_next_frame.ns = 1_000_000_000 / 60;
            },
            0xE000...0xEFFF => {
                const skip_if_pressed = switch (inst.nibbles.xnn.nn) {
                    0x9E => true,
                    0xA1 => false,
                    else => invalid_inst(inst_bits),
                };
                const vx = self.registers.v[inst.nibbles.xnn.x];
                if (self.input.keys[vx] == skip_if_pressed) {
                    self.registers.pc += 2;
                }
            },
            0xF000...0xFFFF => {
                const x = inst.nibbles.xnn.x;
                switch (inst.nibbles.xnn.nn) {
                    // Timers
                    0x07 => self.registers.v[x] = self.delay.to_seconds(),
                    0x15 => self.delay = Countdown.from_u8_seconds(self.registers.v[x]),
                    0x18 => self.sound = Countdown.from_u8_seconds(self.registers.v[x]),

                    0x1E => {
                        self.registers.i += self.registers.v[x];
                        self.registers.v[0xF] = @intFromBool(self.registers.i > 0x0FFF);
                        self.registers.i &= 0x0FFF;
                    },
                    0x0A => {
                        switch (self.input.key_just_released) {
                            .key => |k| self.registers.v[x] = k,
                            .none => self.registers.pc -= 2,
                        }
                    },
                    0x29 => {
                        const reg_nibble = self.registers.v[x] & 0xF;
                        const offset: u16 = @truncate(reg_nibble * (FONT.len / 16));
                        self.registers.i = Memory.font_start + offset;
                    },
                    0x33 => {
                        const hex = self.registers.v[x];

                        const ones = hex % 10;
                        const tens = (hex % 100 - ones) / 10;
                        const hundreds = (hex - tens - ones) / 100;

                        self.memory.contiguous[self.registers.i + 0] = hundreds;
                        self.memory.contiguous[self.registers.i + 1] = tens;
                        self.memory.contiguous[self.registers.i + 2] = ones;
                    },

                    0x55 => {
                        const count: usize = x;
                        for (0..count + 1) |reg| {
                            self.memory.contiguous[self.registers.i] = self.registers.v[reg];
                            self.registers.i += 1;
                        }
                    },
                    0x65 => {
                        const count: usize = x;
                        for (0..count + 1) |reg| {
                            self.registers.v[reg] = self.memory.contiguous[self.registers.i];
                            self.registers.i += 1;
                        }
                    },
                    else => invalid_inst(inst_bits),
                }
            },
        }
        self.input.key_just_released = .none;
    }

    fn invalid_inst(inst_bits: u16) noreturn {
        // TODO handle invalid instructions
        std.debug.panic("Invalid instruction: 0x{x}\n", .{inst_bits});
    }

    pub const Memory = extern union {
        sections: extern struct {
            reserved0: [font_start]u8 = std.mem.zeroes([0x0050]u8),
            font: [0x0050]u8 = FONT,
            reserved1: [0x0160]u8 = undefined,
            ram: [0x0E00]u8 = undefined,
        },
        contiguous: [0x1000]u8,
        instructions: [0x0800]u16,

        pub const font_start = 0x0050;
    };

    pub const Stack = struct {
        sp: u8 = 0,
        data: [0x10]u16 = undefined,

        pub fn push(self: *Stack, addr: u16) void {
            self.data[self.sp] = addr;
            self.sp += 1;
        }

        pub fn pop(self: *Stack) u16 {
            self.sp -= 1;
            return self.data[self.sp];
        }
    };

    pub const Registers = struct {
        pc: u16 = 0x0100,
        i: u16 = 0,
        v: [16]u8 = @bitCast(@as(u128, 0)),
    };

    pub const Instruction = packed struct(u16) {
        nibbles: packed union {
            nnn: NNN,
            xnn: XNN,
            xyn: XYN,
            xyo: XYO,
        },
        opcode: Opcode,

        const NNN = packed struct(u12) {
            nnn: u12,
        };
        const XNN = packed struct(u12) {
            nn: u8,
            x: u4,
        };
        const XYN = packed struct(u12) {
            n: u4,
            y: u4,
            x: u4,
        };
        const XYO = packed struct(u12) {
            al: u4,
            y: u4,
            x: u4,
        };

        // TODO
        const Opcode = enum(u4) {
            // zig fmt: off
            // Arithmetic and logic
            pub const AL = enum(u4) {
                assign = 0x0,
                @"or"  = 0x1,
                @"and" = 0x2,
                xor    = 0x3,
                add    = 0x4,
                subxy  = 0x5,
                shr    = 0x6,
                subyx  = 0x7,
                shl    = 0xE,
            };
            // zig fmt: on
        };
    };

    pub const Input = struct {
        keys: [16]bool = .{false} ** 16,
        mappings: packed struct {
            @"0": glfw.Key,
            @"1": glfw.Key,
            @"2": glfw.Key,
            @"3": glfw.Key,
            @"4": glfw.Key,
            @"5": glfw.Key,
            @"6": glfw.Key,
            @"7": glfw.Key,
            @"8": glfw.Key,
            @"9": glfw.Key,
            A: glfw.Key,
            B: glfw.Key,
            C: glfw.Key,
            D: glfw.Key,
            E: glfw.Key,
            F: glfw.Key,
        },
        key_just_released: union(enum) { key: u4, none } = .none,

        pub fn on_key_event(glfw_window: *glfw.Window, key: glfw.Key, _: c_int, action: glfw.Action, _: glfw.Mods) callconv(.c) void {
            if (key == .escape) {
                glfw_window.setShouldClose(true);
                return;
            }

            const self = glfw.getWindowUserPointer(glfw_window, CHIP8) orelse unreachable;
            const mappings_array: [16]glfw.Key = @bitCast(self.input.mappings);

            for (mappings_array, 0..) |mapped_key, i| {
                if (key == mapped_key) {
                    if (action == .release) {
                        self.input.key_just_released = .{ .key = @truncate(i) };
                        self.input.keys[i] = false;
                    } else {
                        self.input.keys[i] = true;
                    }
                    log.debug("Keypress: {s}, set key 0x{x} to {}", .{
                        @tagName(key),
                        i,
                        action != .release,
                    });
                }
            }
        }
    };

    pub const Countdown = struct {
        ns: u64,

        pub fn to_seconds(self: Countdown) u8 {
            return @truncate(self.ns / 1_000_000_000);
        }

        pub fn from_u8_seconds(from: u8) Countdown {
            const extended_from: u64 = from;
            return .{ .ns = extended_from * 1_000_000_000 };
        }
    };
};

test "load immediate" {
    var display: [SCREEN_HEIGHT][SCREEN_WIDTH]u8 = undefined;
    var cpu = CHIP8.init(&display, &.{
        0x60, 0xED,
        0x61, 0xBF,
        0x6F, 0x00,
        0x60, 0xFF,
    });

    cpu.cycle();
    cpu.cycle();
    cpu.cycle();
    cpu.cycle();

    try t.expectEqual(0xFF, cpu.registers.v[0x0]);
    try t.expectEqual(0xBF, cpu.registers.v[0x1]);
    try t.expectEqual(0x00, cpu.registers.v[0xF]);
}

test "load index" {
    var display: [SCREEN_HEIGHT][SCREEN_WIDTH]u8 = undefined;
    var cpu = CHIP8.init(&display, &.{
        0xA1, 0x12,
        0xAF, 0xFF,
        0xA0, 0x00,
    });

    cpu.cycle();
    try t.expectEqual(0x112, cpu.registers.i);

    cpu.cycle();
    try t.expectEqual(0xFFF, cpu.registers.i);

    cpu.cycle();
    try t.expectEqual(0x000, cpu.registers.i);
}

test "font char offset" {
    var display: [SCREEN_HEIGHT][SCREEN_WIDTH]u8 = undefined;
    var cpu = CHIP8.init(&display, &.{
        0x60, 0x00,
        0xF0, 0x29,

        0x61, 0x01,
        0xF1, 0x29,

        0x62, 0x01,
        0xF2, 0x29,

        0x63, 0x0F,
        0xF3, 0x29,
    });

    cpu.cycle();
    cpu.cycle();
    try t.expectEqual(0x50, cpu.registers.i);

    cpu.cycle();
    cpu.cycle();
    try t.expectEqual(0x55, cpu.registers.i);

    cpu.cycle();
    cpu.cycle();
    try t.expectEqual(0x55, cpu.registers.i);

    cpu.cycle();
    cpu.cycle();
    try t.expectEqual(0x9B, cpu.registers.i);
}

test "decimal conversion" {
    var display: [SCREEN_HEIGHT][SCREEN_WIDTH]u8 = undefined;
    var cpu = CHIP8.init(&display, &.{
        0xAF, 0x00,
        0x60, 0x80,
        0xF0, 0x33,
    });

    cpu.cycle();
    cpu.cycle();
    cpu.cycle();
    try t.expectEqual(1, cpu.memory.contiguous[cpu.registers.i + 0]);
    try t.expectEqual(2, cpu.memory.contiguous[cpu.registers.i + 1]);
    try t.expectEqual(8, cpu.memory.contiguous[cpu.registers.i + 2]);
}
