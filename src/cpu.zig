const std = @import("std");
const random = std.crypto.random;
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

// TODO: Stop being a smartass about the types :(
pub const CHIP_8 = struct {
    memory: Memory,
    stack: Stack, // Cheat a little and have the stack outside of RAM
    registers: Registers,
    // Timers
    delay: u8,
    sound: u8,
    display: *[32][64]u8,

    pub fn init(display: *[32][64]u8) CHIP_8 {
        comptime assert(@sizeOf(Memory) == 4096);
        var memory: Memory = .{};

        const ch8 = @embedFile("2-ibm-logo.ch8");
        @memcpy(memory.ram[0..ch8.len], ch8);
        const pc = 0x0000;
        return .{
            .memory = memory,
            .stack = .{},
            .registers = .{ .pc = pc },
            .delay = 0,
            .sound = 0,
            .display = display,
        };
    }

    pub fn cycle(self: *CHIP_8) void {
        const inst_raw = self.memory.instructions()[self.registers.pc];
        self.registers.pc += 1;
        self.execute(inst_raw);
    }

    pub fn execute(self: *CHIP_8, inst_raw: u16) void {
        const inst: Instruction = @bitCast(@byteSwap(inst_raw));
        const inst_bits = @byteSwap(inst_raw);

        switch (inst_bits) {
            0x0000...0x0FFF => {
                switch (inst_bits) {
                    0x00E0 => { // Clear screen
                        self.display.* = std.mem.zeroes([32][64]u8);
                        self.display[31][0] = 0b1100111;
                    },
                    0x00EE => self.registers.pc = self.stack.pop(), // Return
                    else => {
                        std.debug.print("Invalid inst: 0x{x}\n", .{inst_bits});
                        @panic("");
                    },
                }
            },
            0x1000...0x1FFF => {
                const nnn = inst.nibbles.nnn.nnn;
                const addr: u16 = ((nnn & 8) << 4) | (nnn >> 8);
                self.registers.pc = addr;
            }, // Jump
            0x2000...0x2FFF => { // Call
                self.stack.push(self.registers.pc);
                self.registers.pc = inst.nibbles.nnn.nnn;
            },
            0x3000...0x3FFF => { // Skip if VX == NN
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                if (self.registers.v[x] == nn) {
                    self.registers.pc += 1;
                }
            },
            0x4000...0x4FFF => { // Skip if VX != NN
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                if (self.registers.v[x] != nn) {
                    self.registers.pc += 1;
                }
            },
            0x5000...0x5FFF => skip: { // Skip if VX == VY // TODO: Combine with 0x9XYN
                const xyn = inst.nibbles.xyn;
                if (xyn.n != 0) break :skip;
                assert(inst_bits & 0xF == xyn.n);
                if (self.registers.v[xyn.x] == self.registers.v[xyn.y]) {
                    self.registers.pc += 1;
                }
            },
            0x9000...0x9FFF => skip: { // Skip if VX != VY
                if (inst.nibbles.xyn.n != 0) break :skip;
                const xyn = inst.nibbles.xyn;
                if (self.registers.v[xyn.x] != self.registers.v[xyn.y]) {
                    self.registers.pc += 1;
                }
            },
            0x6000...0x6FFF => {
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                self.registers.v[x] = nn;
            }, // Set VX to NN
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
            0xA000...0xAFFF => {
                std.debug.print("Wrote value {d} to index register\n", .{inst.nibbles.nnn.nnn});
                self.registers.i = inst.nibbles.nnn.nnn;
            },
            0xB000...0xBFFF => self.registers.pc = inst.nibbles.nnn.nnn + self.registers.v[0], // TODO: Configurable behaviour
            0xC000...0xCFFF => {
                const x = inst.nibbles.xnn.x;
                const nn = inst.nibbles.xnn.nn;
                var rand = random.int(u8);
                rand &= nn;
                self.registers.v[x] = rand;
            },
            0xD000...0xDFFF => {
                const x = inst.nibbles.xyn.x;
                const y = inst.nibbles.xyn.y;
                const n = inst.nibbles.xyn.n;
                std.debug.print("d: {d}, x: {d}, y: {d}, n: {d}, n actual: {d}\n", .{ @intFromEnum(inst.opcode), x, y, n, inst_bits & 0xF });
                assert(inst_bits & 0xF == n);

                const x_coord: u16 = self.registers.v[x] % 64;
                const y_coord: u16 = 31 - self.registers.v[y] % 32;

                self.registers.v[0xF] = 0;

                for (0..n) |byte| {
                    for (0..8) |i| {
                        self.display[(y_coord + byte) % 32][x_coord + i] = 255;
                    }
                }
            },
            else => std.debug.print("Invalid inst: 0x{x}\n", .{inst_bits}),
        }
    }

    pub const Memory = extern struct {
        reserved0: [0x0050]u8 = std.mem.zeroes([0x0050]u8),
        font: [0x0050]u8 = FONT,
        reserved1: [0x0160]u8 = undefined,
        ram: [0x0E00]u8 = undefined,

        pub inline fn contiguous(self: Memory) [0x1000]u8 {
            return @bitCast(self);
        }

        pub inline fn instructions(self: Memory) [0x0700]u16 {
            return @bitCast(self.ram);
        }
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
