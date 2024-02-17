const std = @import("std");

const INSTRUCTION_SIZE: u32 = 4;

pub const Step = enum {
    cont,
    exit,
};

pub const Cpu = struct {
    registers: [32]u32,
    pc: u32,
    counter: usize,

    pub fn init() Cpu {
        return .{
            .registers = [_]u32{0} ** 32,
            .pc = 0,
            .counter = 0,
        };
    }

    pub fn step(self: *Cpu, mem: []u8) Step {
        const instruction = std.mem.bytesToValue(u32, mem[self.pc .. self.pc + 4]);
        if (std.meta.intToEnum(OpCode, opcode(instruction))) |op| {
            std.debug.print("{} {}\n", .{ self.counter, op });
            self.counter += 1;
            switch (op) {
                .op_imm => {
                    const function = funct3(instruction);
                    switch (function) {
                        op_imm.ADDI => {
                            const source_register = rs1(instruction);
                            const dest_register = rd(instruction);
                            const immediate = i_imm(instruction);
                            const source_value: i32 = @bitCast(self.registers[source_register]);
                            std.debug.print("addi: {} {}\n", .{ source_value, immediate });
                            const new_value = source_value + immediate;
                            self.registers[dest_register] = @bitCast(new_value);
                        },
                        else => {
                            std.debug.print("invalid function: {}\n", .{function});
                            return .exit;
                        },
                    }
                    self.pc += INSTRUCTION_SIZE;
                    return .cont;
                },
                .jal => {
                    const dest_register = rd(instruction);
                    const imm_value = j_imm(instruction);
                    const new_pc: u32 = @intCast(@as(i32, @intCast(self.pc)) + imm_value);
                    self.registers[dest_register] = self.pc + 4;
                    self.pc = new_pc;
                    if (self.pc & 0b11 != 0) {
                        std.debug.print("unaligned instruction\n", .{});
                        return .exit;
                    }
                    return .cont;
                },
                .load => {
                    const source_register = rs1(instruction);
                    const offset = i_imm(instruction);
                    const dest_register = rd(instruction);
                    const source_address: u32 = @intCast(@as(i32, @intCast(self.registers[source_register])) + offset);
                    const function = funct3(instruction);
                    switch (function) {
                        load.LB => self.registers[dest_register] = @intCast(@as(i8, @intCast(mem[source_address]))),
                        load.LH => self.registers[dest_register] = @intCast(std.mem.bytesToValue(i16, mem[source_address .. source_address + 2])),
                        load.LW => self.registers[dest_register] = @intCast(std.mem.bytesToValue(i32, mem[source_address .. source_address + 4])),
                        load.LBU => self.registers[dest_register] = @as(u8, @intCast(mem[source_address])),
                        load.LHU => self.registers[dest_register] = std.mem.bytesToValue(u16, mem[source_address .. source_address + 2]),
                        else => {
                            std.debug.print("invalid function: {}\n", .{function});
                            return .exit;
                        },
                    }
                    self.pc += INSTRUCTION_SIZE;
                    return .cont;
                },
                .store => {
                    const dest_register = rs1(instruction);
                    const offset = s_imm(instruction);
                    const dest_address: u32 = @intCast(@as(i32, @intCast(self.registers[dest_register])) + offset);
                    const source_value = self.registers[rs2(instruction)];
                    const function = funct3(instruction);
                    switch (function) {
                        store.SB => mem[dest_address] = @intCast(source_value),
                        store.SH => {
                            const val: u16 = @intCast(source_value);
                            @memcpy(mem[dest_address .. dest_address + 2], &std.mem.toBytes(val));
                        },
                        store.SW => {
                            const val: u32 = @intCast(source_value);
                            @memcpy(mem[dest_address .. dest_address + 4], &std.mem.toBytes(val));
                        },
                        else => {
                            std.debug.print("invalid function: {}\n", .{function});
                            return .exit;
                        },
                    }
                    self.pc += INSTRUCTION_SIZE;
                    return .cont;
                },
                else => return .exit,
            }
        } else |_| {
            std.debug.print("invalid opcode: {}\n", .{instruction});
            return .exit;
        }
    }
};

// funct3

const op_imm = struct {
    const ADDI: u8 = 0b000;
    const SLLI: u8 = 0b001;
    const SLTI: u8 = 0b010;
    const XORI: u8 = 0b100;
    const SLTIU: u8 = 0b011;
    const ORI: u8 = 0b110;
    const ANDI: u8 = 0b111;
    const SRLI_OR_SRAI: u8 = 0b101;
};

const load = struct {
    const LB: u8 = 0b000;
    const LH: u8 = 0b001;
    const LW: u8 = 0b010;
    const LBU: u8 = 0b100;
    const LHU: u8 = 0b101;
};

const store = struct {
    const SB: u8 = 0b000;
    const SH: u8 = 0b001;
    const SW: u8 = 0b010;
};

fn opcode(instruction: u32) usize {
    return extract(instruction, 0, C_7_BITS);
}

fn rd(instruction: u32) usize {
    return extract(instruction, 7, C_5_BITS);
}

fn rs1(instruction: u32) usize {
    return extract(instruction, 15, C_5_BITS);
}

fn rs2(instruction: u32) usize {
    return extract(instruction, 20, C_5_BITS);
}

fn funct3(instruction: u32) u8 {
    return @truncate(extract(instruction, 12, C_3_BITS));
}

fn funct7(instruction: u32) u8 {
    return @truncate(extract(instruction, 25, C_7_BITS));
}

fn sign_extend_32(raw_value: u32, bits: u5, sign_bit: bool) i32 {
    const bit_mask = (@as(u32, 1) << bits) - 1;
    const sign_mask = ~bit_mask;
    const extension = if (sign_bit) sign_mask else 0;
    return @bitCast((raw_value & bit_mask) | extension);
}

fn i_imm(instruction: u32) i32 {
    const sign_bit = extract(instruction, 0, SIGN_BIT) != 0;
    const raw_value = extract(instruction, 20, C_11_BITS);
    return sign_extend_32(raw_value, 11, sign_bit);
}

fn s_imm(instruction: u32) i32 {
    const sign_bit = extract(instruction, 0, SIGN_BIT) != 0;
    const upper_6_bits = extract(instruction, 25, C_6_BITS) << 5;
    const lower_5_bits = extract(instruction, 7, C_5_BITS);
    return sign_extend_32(upper_6_bits | lower_5_bits, 11, sign_bit);
}

fn j_imm(instruction: u32) i32 {
    const sign_bit = instruction & SIGN_BIT != 0;
    const bit_11 = extract(instruction, 20, 0b1) << 11;
    const bits_10_to_1 = extract(instruction, 21, C_10_BITS) << 1;
    const bits_12_to_19 = extract(instruction, 12, C_8_BITS) << 12;
    return sign_extend_32(bits_12_to_19 | bit_11 | bits_10_to_1, 20, sign_bit);
}

// decoder

const SIGN_BIT: u32 = 0b1000_0000_0000_0000_0000_0000_0000_0000;
const C_11_BITS: u32 = 0b111_1111_1111;
const C_10_BITS: u32 = 0b11_1111_1111;
const C_8_BITS: u32 = 0b1111_1111;
const C_7_BITS: u32 = 0b111_1111;
const C_6_BITS: u32 = 0b11_1111;
const C_5_BITS: u32 = 0b1_1111;
const C_4_BITS: u32 = 0b1111;
const C_3_BITS: u32 = 0b111;

fn extract(value: u32, shift: u5, mask: u32) u32 {
    return (value >> shift) & mask;
}

// op codes

fn opcodeValue(col: u8, row: u8) u32 {
    const col_shifted = (col & 0b111) << 2;
    const row_shifted = (row & 0b11) << 5;
    return (col_shifted | row_shifted | 0b11);
}

pub const OpCode = enum(u32) {
    op = opcodeValue(0b100, 0b01),
    op_imm = opcodeValue(0b100, 0b00),
    jal = opcodeValue(0b011, 0b11),
    jalr = opcodeValue(0b001, 0b11),
    lui = opcodeValue(0b101, 0b01),
    auipc = opcodeValue(0b101, 0b00),
    branch = opcodeValue(0b000, 0b11),
    load = opcodeValue(0b000, 0b00),
    store = opcodeValue(0b000, 0b01),
    fence = opcodeValue(0b011, 0b00),
    system = opcodeValue(0b100, 0b11),
};
