const std = @import("std");

pub const CpuKind = enum {
    rv32,
    rv64,
};

pub fn Cpu(comptime cpu_kind: CpuKind) type {
    return struct {
        registers: [32]URegister,
        pc: URegister,
        csrs: struct {
            rdcycle: u64,
            instret: u64,
            rdtime: u64,
            test_register: URegister,
        },

        const URegister = switch (cpu_kind) {
            .rv32 => u32,
            .rv64 => u64,
        };
        const IRegister = switch (cpu_kind) {
            .rv32 => i32,
            .rv64 => i64,
        };
        const register_size = @sizeOf(URegister);
        const Step = union(enum) {
            cont,
            exit,
            system: URegister,
        };

        pub fn init() Cpu(cpu_kind) {
            return .{
                .registers = [_]URegister{0} ** 32,
                .pc = 0,
                .csrs = .{
                    .rdcycle = 0,
                    .instret = 0,
                    .rdtime = 0,
                    .test_register = 0,
                },
            };
        }

        pub fn step(self: *Cpu(cpu_kind), mem: []u8) !Step {
            const next_byte = mem[self.pc];

            const next_bits_4_2: u3 = @intCast((next_byte >> 2) & 0b111);
            if (next_bits_4_2 == 0b111) {
                return error.InstructionSizeNotSupported;
            }

            const next_bits_1_0: u2 = @intCast(next_byte & 0b11);
            switch (next_bits_1_0) {
                0b00, 0b01, 0b10 => {
                    const instruction_size = @sizeOf(u16);
                    const instruction = std.mem.littleToNative(u16, std.mem.bytesToValue(u16, mem[self.pc .. self.pc + instruction_size]));

                    if (std.meta.intToEnum(OpCode16, opcode_16(instruction))) |op| {
                        switch (op) {
                            .jalr => return error.NotImplemented,
                        }
                    } else |_| {
                        return error.InvalidOpcode16;
                    }
                },
                0b11 => {
                    const instruction_size = @sizeOf(u32);
                    const instruction = std.mem.littleToNative(u32, std.mem.bytesToValue(u32, mem[self.pc .. self.pc + instruction_size]));

                    if (std.meta.intToEnum(OpCode32, opcode_32(instruction))) |op| {
                        switch (op) {
                            .op => return error.NotImplemented,
                            .op_imm => {
                                const function = funct3_32(instruction);
                                switch (function) {
                                    op_imm.ADDI => {
                                        const source_register = rs1_32(instruction);
                                        const dest_register = rd_32(instruction);
                                        const immediate = i_imm_32(instruction);
                                        const source_value: IRegister = @intCast(self.registers[source_register]);
                                        const new_value = source_value + immediate;
                                        self.set_register(dest_register, @intCast(new_value));
                                    },
                                    else => return error.InvalidFunction,
                                }
                                self.pc += instruction_size;
                                return .cont;
                            },
                            .jal => {
                                const dest_register = rd_32(instruction);
                                const imm_value = j_imm_32(instruction);
                                const new_pc: URegister = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                self.set_register(dest_register, self.pc + register_size);
                                self.pc = new_pc;
                                if (self.pc & 0b11 != 0) {
                                    return error.UnalignedInstruction;
                                }
                                return .cont;
                            },
                            .jalr => {
                                const source_register = rs1_32(instruction);
                                const source_value: IRegister = @intCast(self.registers[source_register]);
                                const dest_register = rd_32(instruction);
                                const imm_value = i_imm_32(instruction);
                                const new_pc = @as(URegister, @intCast(source_value + imm_value)) & ~@as(URegister, 1);
                                self.set_register(dest_register, self.pc + register_size);
                                self.pc = new_pc;
                                return .cont;
                            },
                            .lui => return error.NotImplemented,
                            .auipc => return error.NotImplemented,
                            .branch => {
                                const source1_register = rs1_32(instruction);
                                const source2_register = rs2_32(instruction);
                                const offset = b_imm_32(instruction);
                                const function = funct3_32(instruction);
                                const cond = switch (function) {
                                    branch.BEQ => @as(IRegister, @intCast(self.registers[source1_register])) == @as(IRegister, @intCast(self.registers[source2_register])),
                                    branch.BNE => @as(IRegister, @intCast(self.registers[source1_register])) != @as(IRegister, @intCast(self.registers[source2_register])),
                                    branch.BLT => @as(IRegister, @intCast(self.registers[source1_register])) < @as(IRegister, @intCast(self.registers[source2_register])),
                                    branch.BGE => @as(IRegister, @intCast(self.registers[source1_register])) >= @as(IRegister, @intCast(self.registers[source2_register])),
                                    branch.BLTU => self.registers[source1_register] < self.registers[source2_register],
                                    branch.BGEU => self.registers[source1_register] >= self.registers[source2_register],
                                    else => return error.InvalidFunction,
                                };
                                if (cond) {
                                    self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + offset);
                                } else {
                                    self.pc += instruction_size;
                                }
                                return .cont;
                            },
                            .load => {
                                const source_register = rs1_32(instruction);
                                const offset = i_imm_32(instruction);
                                const dest_register = rd_32(instruction);
                                const source_address: URegister = @intCast(@as(IRegister, @intCast(self.registers[source_register])) + offset);
                                const function = funct3_32(instruction);
                                switch (function) {
                                    load.LB => self.set_register(dest_register, @intCast(@as(i8, @intCast(mem[source_address])))),
                                    load.LH => self.set_register(dest_register, @intCast(std.mem.bytesToValue(i16, mem[source_address .. source_address + 2]))),
                                    load.LW => self.set_register(dest_register, @intCast(std.mem.bytesToValue(i32, mem[source_address .. source_address + 4]))),
                                    load.LBU => self.set_register(dest_register, @as(u8, @intCast(mem[source_address]))),
                                    load.LHU => self.set_register(dest_register, std.mem.bytesToValue(u16, mem[source_address .. source_address + 2])),
                                    else => return error.InvalidFunction,
                                }
                                self.pc += instruction_size;
                                return .cont;
                            },
                            .store => {
                                const dest_register = rs1_32(instruction);
                                const offset = s_imm_32(instruction);
                                const dest_address: URegister = @intCast(@as(IRegister, @intCast(self.registers[dest_register])) + offset);
                                const source_value = self.registers[rs2_32(instruction)];
                                const function = funct3_32(instruction);
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
                                    else => return error.InvalidFunction,
                                }
                                self.pc += instruction_size;
                                return .cont;
                            },
                            .fence => return error.NotImplemented,
                            .system => {
                                const function = funct3_32(instruction);
                                switch (function) {
                                    system.ECALL_OR_EBREAK => {
                                        const ECALL = 0;
                                        const EBREAK = 1;
                                        switch (i_imm_32(instruction)) {
                                            ECALL => {
                                                self.pc += instruction_size;
                                                return .{ .system = self.registers[10] };
                                            },
                                            EBREAK => {
                                                return error.NotImplemented;
                                            },
                                            else => return error.InvalidParameter,
                                        }
                                    },
                                    system.CSRRW => {
                                        const csr_address: usize = csr_32(instruction);
                                        const csr_value = try self.get_csr(csr_address);
                                        const source_register = rs1_32(instruction);
                                        const source_value = self.registers[source_register];
                                        const dest_register = rd_32(instruction);
                                        if (dest_register != 0) {
                                            self.set_register(dest_register, csr_value);
                                        }
                                        try self.set_csr(csr_address, source_value);
                                    },
                                    system.CSRRS => {
                                        const csr_address: usize = csr_32(instruction);
                                        const csr_value = try self.get_csr(csr_address);
                                        const source_register = rs1_32(instruction);
                                        const source_value = self.registers[source_register];
                                        const dest_register = rd_32(instruction);
                                        if (dest_register != 0) {
                                            self.set_register(dest_register, csr_value);
                                        }
                                        if (source_value != 0) {
                                            try self.set_csr(csr_address, csr_value | source_value);
                                        }
                                    },
                                    system.CSRRC => {
                                        const csr_address: usize = csr_32(instruction);
                                        const csr_value = try self.get_csr(csr_address);
                                        const source_register = rs1_32(instruction);
                                        const source_value = self.registers[source_register];
                                        const dest_register = rd_32(instruction);
                                        if (dest_register != 0) {
                                            self.set_register(dest_register, csr_value);
                                        }
                                        if (source_value != 0) {
                                            try self.set_csr(csr_address, csr_value & (~source_value));
                                        }
                                    },
                                    system.CSRRWI => {
                                        const csr_address: usize = csr_32(instruction);
                                        const csr_value = try self.get_csr(csr_address);
                                        const source_register: URegister = @intCast(rs1_32(instruction));
                                        const source_value = self.registers[source_register];
                                        const dest_register = rd_32(instruction);
                                        if (dest_register != 0) {
                                            self.set_register(dest_register, csr_value);
                                        }
                                        try self.set_csr(csr_address, source_value);
                                    },
                                    system.CSRRSI => {
                                        const csr_address: usize = csr_32(instruction);
                                        const csr_value = try self.get_csr(csr_address);
                                        const source_register: URegister = @intCast(rs1_32(instruction));
                                        const source_value = self.registers[source_register];
                                        const dest_register = rd_32(instruction);
                                        if (dest_register != 0) {
                                            self.set_register(dest_register, csr_value);
                                        }
                                        if (source_value != 0) {
                                            try self.set_csr(csr_address, csr_value | source_value);
                                        }
                                    },
                                    system.CSRRCI => {
                                        const csr_address: usize = csr_32(instruction);
                                        const csr_value = try self.get_csr(csr_address);
                                        const source_register: URegister = @intCast(rs1_32(instruction));
                                        const source_value = self.registers[source_register];
                                        const dest_register = rd_32(instruction);
                                        if (dest_register != 0) {
                                            self.set_register(dest_register, csr_value);
                                        }
                                        if (source_value != 0) {
                                            try self.set_csr(csr_address, csr_value & (~source_value));
                                        }
                                    },
                                    else => return error.InvalidFunction,
                                }
                                self.pc += instruction_size;
                                return .cont;
                            },
                        }
                    } else |_| {
                        return error.InvalidOpcode32;
                    }
                },
            }
        }

        fn set_register(self: *Cpu(cpu_kind), register: usize, value: URegister) void {
            if (register != 0) {
                self.registers[register] = value;
            }
        }

        fn get_csr(self: Cpu(cpu_kind), address: usize) !URegister {
            return switch (address) {
                0x1 => self.csrs.test_register,
                0xC00 => @intCast(self.csrs.rdcycle),
                0xC80 => @intCast(self.csrs.rdcycle >> 32),
                0xC01 => @intCast(self.csrs.rdtime),
                0xC81 => @intCast(self.csrs.rdtime >> 32),
                0xC02 => @intCast(self.csrs.instret),
                0xC82 => @intCast(self.csrs.instret >> 32),
                else => return error.InvalidCsrAddress,
            };
        }

        fn set_csr(self: *Cpu(cpu_kind), address: usize, value: URegister) !void {
            switch (address) {
                0x1 => self.csrs.test_register = value,
                else => return error.InvalidCsrAddress,
            }
        }
    };
}

// op codes

pub const OpCode32 = enum(u32) {
    op = 0b01100_11,
    op_imm = 0b00100_11,
    jal = 0b11011_11,
    jalr = 0b11001_11,
    lui = 0b01101_11,
    auipc = 0b00101_11,
    branch = 0b11000_11,
    load = 0b00000_11,
    store = 0b01000_11,
    fence = 0b00011_11,
    system = 0b11100_11,
};

pub const OpCode16 = enum(u16) {
    jalr = 0b00000_10,
};

// decoder

const SIGN_BIT_32: u32 = 0b1000_0000_0000_0000_0000_0000_0000_0000;
const C_11_BITS: u32 = 0b111_1111_1111;
const C_10_BITS: u32 = 0b11_1111_1111;
const C_8_BITS: u32 = 0b1111_1111;
const C_7_BITS: u32 = 0b111_1111;
const C_6_BITS: u32 = 0b11_1111;
const C_5_BITS: u32 = 0b1_1111;
const C_4_BITS: u32 = 0b1111;
const C_3_BITS: u32 = 0b111;

fn extract_32(value: u32, shift: u5, mask: u32) u32 {
    return (value >> shift) & mask;
}

fn extract_16(value: u16, shift: u4, mask: u16) u16 {
    return (value >> shift) & mask;
}

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

const branch = struct {
    const BEQ: u8 = 0b000;
    const BNE: u8 = 0b001;
    const BLT: u8 = 0b100;
    const BGE: u8 = 0b101;
    const BLTU: u8 = 0b110;
    const BGEU: u8 = 0b111;
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

const system = struct {
    const ECALL_OR_EBREAK: u8 = 0b000;
    const CSRRW: u8 = 0b001;
    const CSRRS: u8 = 0b010;
    const CSRRC: u8 = 0b011;
    const CSRRWI: u8 = 0b101;
    const CSRRSI: u8 = 0b110;
    const CSRRCI: u8 = 0b111;
};

fn opcode_32(instruction: u32) usize {
    return extract_32(instruction, 0, C_7_BITS);
}

fn opcode_16(instruction: u16) usize {
    return extract_16(instruction, 0, C_7_BITS);
}

fn rd_32(instruction: u32) usize {
    return extract_32(instruction, 7, C_5_BITS);
}

fn rs1_32(instruction: u32) usize {
    return extract_32(instruction, 15, C_5_BITS);
}

fn rs2_32(instruction: u32) usize {
    return extract_32(instruction, 20, C_5_BITS);
}

fn funct3_32(instruction: u32) u8 {
    return @truncate(extract_32(instruction, 12, C_3_BITS));
}

fn funct7_32(instruction: u32) u8 {
    return @truncate(extract_32(instruction, 25, C_7_BITS));
}

fn csr_32(instruction: u32) u32 {
    return extract_32(instruction, 20, 0b1111_1111_1111);
}

fn sign_extend_32(raw_value: u32, bits: u5, sign_bit: bool) i32 {
    const bit_mask = (@as(u32, 1) << bits) - 1;
    const sign_mask = ~bit_mask;
    const extension = if (sign_bit) sign_mask else 0;
    return @bitCast((raw_value & bit_mask) | extension);
}

fn i_imm_32(instruction: u32) i32 {
    const sign_bit = extract_32(instruction, 0, SIGN_BIT_32) != 0;
    const raw_value = extract_32(instruction, 20, C_11_BITS);
    return sign_extend_32(raw_value, 11, sign_bit);
}

fn s_imm_32(instruction: u32) i32 {
    const sign_bit = extract_32(instruction, 0, SIGN_BIT_32) != 0;
    const upper_6_bits = extract_32(instruction, 25, C_6_BITS) << 5;
    const lower_5_bits = extract_32(instruction, 7, C_5_BITS);
    return sign_extend_32(upper_6_bits | lower_5_bits, 11, sign_bit);
}

fn b_imm_32(instruction: u32) i32 {
    const sign_bit = instruction & SIGN_BIT_32 != 0;
    const bit_11 = extract_32(instruction, 7, 0b1) << 11;
    const bits_10_to_5 = extract_32(instruction, 25, C_6_BITS) << 5;
    const bits_4_to_1 = extract_32(instruction, 8, C_4_BITS) << 1;
    return sign_extend_32(bit_11 | bits_10_to_5 | bits_4_to_1, 12, sign_bit);
}

fn j_imm_32(instruction: u32) i32 {
    const sign_bit = instruction & SIGN_BIT_32 != 0;
    const bit_11 = extract_32(instruction, 20, 0b1) << 11;
    const bits_10_to_1 = extract_32(instruction, 21, C_10_BITS) << 1;
    const bits_12_to_19 = extract_32(instruction, 12, C_8_BITS) << 12;
    return sign_extend_32(bits_12_to_19 | bit_11 | bits_10_to_1, 20, sign_bit);
}
