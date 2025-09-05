const std = @import("std");
const t = std.testing;

const random = std.crypto.random;
const readInt = std.mem.readInt;

const assert = std.debug.assert;

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
    delay: u8,
    sound: u8,
    input: extern union {
        key: [16]bool,
        key_bits: u8,
    },
    display: *[32][64]u8,

    pub fn init(display: *[32][64]u8, rom: []const u8) CHIP8 {
        comptime assert(@sizeOf(Memory) == 0x1000);
        var memory: Memory = .{ .sections = .{} };

        @memcpy(memory.sections.ram[0..rom.len], rom);
        const pc = 0x0200;
        return .{
            .memory = memory,
            .stack = .{},
            .registers = .{ .pc = pc },
            .delay = 0,
            .sound = 0,
            .input = .{ .key_bits = 0 },
            .display = display,
        };
    }

    pub fn cycle(self: *CHIP8) void {
        const pc = &self.registers.pc;
        const inst_upper: u16 = self.memory.contiguous[pc.*];
        const inst_lower: u16 = self.memory.contiguous[pc.* + 1];
        const inst = inst_upper << 8 | inst_lower;
        pc.* += 2;
        self.delay -|= 1; // TODO: proper timer countdown
        self.sound -|= 1; // TODO: proper timer countdown
        self.execute(inst);
    }

    pub fn execute(self: *CHIP8, inst_bits: u16) void {
        const inst: Instruction = @bitCast(inst_bits);

        std.debug.print("inst: 0x{x}\n", .{inst_bits});

        switch (inst_bits) {
            0x0000...0x0FFF => {
                switch (inst_bits) {
                    0x00E0 => { // Clear screen
                        self.display.* = std.mem.zeroes([32][64]u8);
                        self.display[31][0] = 0b1100111;
                    },
                    0x00EE => self.registers.pc = self.stack.pop(), // Return
                    else => {
                        std.debug.panic("Invalid inst: 0x{x}\n", .{inst_bits});
                    },
                }
            },
            0x1000...0x1FFF => { // Jump
                const nnn = inst.nibbles.nnn.nnn;
                std.debug.print("Jump to 0x{x}\n", .{nnn});
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
            0x5000...0x5FFF => skip: { // Skip if VX == VY // TODO: Combine with 0x9XYN
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
            0x8000...0x8FFF => al: {
                if (inst.nibbles.xyn.n != 0) break :al;

                const x = inst.nibbles.xyo.x;
                const y = inst.nibbles.xyo.y;
                const al = inst.nibbles.xyo.al;
                const vx = &self.registers.v[x];
                const vy = &self.registers.v[y];
                const flags = &self.registers.flags;

                switch (al) {
                    .assign => vx.* = vy.*,
                    .@"or" => vx.* |= vy.*,
                    .@"and" => vx.* &= vy.*,
                    .xor => vx.* ^= vy.*,
                    .add => {
                        vx.* +%= vy.*;
                        if (vy.* > vx.*) flags.carry = 1 else flags.carry = 0;
                    },
                    .subxy => vx.* = vx.* - vy.*,
                    .subyx => vx.* = vy.* - vx.*,
                    .shr => { // TODO: Configurable behaviour
                        flags.carry = @truncate(vx.*);
                        vx.* >>= 1;
                    },
                    .shl => { // TODO: Configurable behaviour
                        flags.carry = @truncate(vx.* >> 7);
                        vx.* <<= 1;
                    },
                    _ => unreachable,
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
            0xB000...0xBFFF => self.registers.pc = inst.nibbles.nnn.nnn + self.registers.v[0], // TODO: Configurable behaviour
            0xC000...0xCFFF => { // Random number and mask
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                var rand = random.int(u8);
                rand &= nn;
                self.registers.v[x] = rand;
            },
            0xD000...0xDFFF => { // Draw
                const x = inst.nibbles.xyn.x;
                const y = inst.nibbles.xyn.y;
                const n = inst.nibbles.xyn.n;
                assert(inst_bits & 0xF == n);

                const x_coord: u16 = self.registers.v[x] % 64;
                const y_coord: u16 = 31 - self.registers.v[y] % 32;

                self.registers.v[0xF] = 0;

                for (0..n) |byte| {
                    const sprite = self.memory.contiguous[self.registers.i + byte];
                    for (0..8) |i| {
                        const pixel = (sprite >> @truncate(7 - i)) & 1;
                        const mask: u8 = if (pixel == 0) 0 else 255;

                        const dest_pixel = &self.display[(y_coord - byte) % 32][x_coord + i];

                        self.registers.v[0xF] = dest_pixel.*;
                        dest_pixel.* ^= mask;
                        self.registers.v[0xF] ^= mask;
                        self.registers.v[0xF] &= 1;
                    }
                }
            },
            0xE000...0xEFFF => keys: {
                const skip_if_pressed = switch (inst.nibbles.xnn.nn) {
                    0x9E => true,
                    0xA1 => false,
                    else => break :keys,
                };
                const x = inst.nibbles.xnn.x;
                if (self.input.key[x] == skip_if_pressed) {
                    self.registers.pc += 2;
                }
            },
            0xF000...0xFFFF => {
                const x = inst.nibbles.xnn.x;
                switch (inst.nibbles.xnn.nn) {
                    // Timers
                    0x07 => self.registers.v[x] = self.delay,
                    0x15 => self.delay = self.registers.v[x],
                    0x18 => self.sound = self.registers.v[x],

                    0x1E => {
                        self.registers.i += self.registers.v[x];
                        self.registers.v[0xF] = @intFromBool(self.registers.i > 0x0FFF);
                        self.registers.i &= 0x0FFF;
                    },
                    0x0A => {
                        if (self.input.key_bits == 0) {
                            self.registers.pc -= 2;
                        } else {
                            const key_idx = @ctz(self.input.key_bits);
                            self.registers.v[x] = key_idx;
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

                    0x55 => { // memcpy? // TODO: Configure incrementing i
                        for (0..x + 1) |reg| {
                            self.memory.contiguous[self.registers.i + reg] = self.registers.v[reg];
                        }
                    },
                    0x65 => { // memcpy?
                        for (0..x + 1) |reg| {
                            self.registers.v[reg] = self.memory.contiguous[self.registers.i + reg];
                        }
                    },
                    else => {},
                }
            },
        }
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
        flags: Flags = @bitCast(@as(u8, 0)),

        const Flags = packed struct(u8) {
            carry: u1,
            _padding: u7,
        };
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
            al: Opcode.AL,
            y: u4,
            x: u4,
        };

        const Opcode = enum(u4) {
            add = 0x0,
            sub = 0x1,
            mul = 0xF,

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
                _,
            };
            // zig fmt: on
        };
    };
};

test "load immediate" {
    var display: [32][64]u8 = undefined;
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
    var display: [32][64]u8 = undefined;
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
    var display: [32][64]u8 = undefined;
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
    var display: [32][64]u8 = undefined;
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
