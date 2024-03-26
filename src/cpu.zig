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
        const URegisterDouble = switch (cpu_kind) {
            .rv32 => u64,
            .rv64 => u128,
        };
        const IRegisterDouble = switch (cpu_kind) {
            .rv32 => i64,
            .rv64 => i128,
        };

        const U_MAX: URegister = std.math.maxInt(URegister);

        pub const Step = union(enum) {
            cont: Instruction,
            exit,
            system: URegister,
        };

        pub fn init() Cpu(cpu_kind) {
            var cpu = Cpu(cpu_kind){
                .registers = [_]URegister{0} ** 32,
                .pc = 0,
                .csrs = .{
                    .rdcycle = 0,
                    .instret = 0,
                    .rdtime = 0,
                    .test_register = 0,
                },
            };
            // set return address to an invalid address.
            // when the pc is set to this, we know to exit.
            cpu.registers[1] = U_MAX;
            return cpu;
        }

        pub fn step(self: *Cpu(cpu_kind), mem: []u8) !Step {
            if (self.pc == U_MAX) {
                return .exit;
            }
            const next_byte = mem[self.pc];
            const next_bits_1_0: u2 = @intCast(next_byte & 0b11);
            switch (@as(InstructionKind, @enumFromInt(next_bits_1_0))) {
                .inst00 => {
                    const instruction_size = @sizeOf(u16);
                    const instruction = std.mem.littleToNative(u16, std.mem.bytesToValue(u16, mem[self.pc .. self.pc + instruction_size]));
                    if (std.meta.intToEnum(Instruction00Kind, funct3_16(instruction))) |inst00_kind| {
                        switch (inst00_kind) {
                            .addi4spn => {
                                const rd_register = 8 + ((instruction >> 2) & 0b111);
                                const imm_value = ciw_uimm_8(instruction);
                                self.set_register(rd_register, self.registers[2] + imm_value);
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst00 = .{ .addi4spn = {} } } };
                            },
                        }
                    } else |_| {
                        return error.InvalidInstruction00Kind;
                    }
                    return error.NotImplemented;
                },
                .inst01 => {
                    const instruction_size = @sizeOf(u16);
                    const instruction = std.mem.littleToNative(u16, std.mem.bytesToValue(u16, mem[self.pc .. self.pc + instruction_size]));
                    if (std.meta.intToEnum(Instruction01Kind, funct3_16(instruction))) |inst01_kind| {
                        const inst01: Instruction01 = blk: {
                            switch (inst01_kind) {
                                .addi => {
                                    const register = rd_16(instruction);
                                    const imm_value = ci_imm(instruction);
                                    const source_value: IRegister = @bitCast(self.registers[register]);
                                    const new_value = source_value + imm_value;
                                    self.set_register(register, @bitCast(new_value));
                                    self.pc += instruction_size;
                                    break :blk .{ .addi = {} };
                                },
                                .jal => {
                                    const imm_value = cj_imm(instruction);
                                    const new_pc: URegister = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                    self.set_register(1, self.pc + instruction_size);
                                    self.pc = new_pc;
                                    break :blk .{ .jal = {} };
                                },
                                .li => {
                                    const dest_register = rd_16(instruction);
                                    const imm_value = ci_imm(instruction);
                                    self.set_register(dest_register, @intCast(imm_value));
                                    self.pc += instruction_size;
                                    break :blk .{ .li = {} };
                                },
                                .ssas => {
                                    const bits_11_to_10: u2 = @intCast((instruction >> 10) & 0b11);
                                    if (std.meta.intToEnum(Instruction01SsasKind, bits_11_to_10)) |inst01_ssas_kind| {
                                        const inst01_ssas: Instruction01Ssas = blk2: {
                                            switch (inst01_ssas_kind) {
                                                .srli => {
                                                    const rd_register = 8 + ((instruction >> 7) & 0b111);
                                                    const new_value = blk3: {
                                                        switch (cpu_kind) {
                                                            .rv32 => {
                                                                const uimm_value = ci_uimm_5(instruction);
                                                                const source_value = self.registers[rd_register];
                                                                break :blk3 source_value >> uimm_value;
                                                            },
                                                            .rv64 => {
                                                                const uimm_value = ci_uimm_6(instruction);
                                                                const source_value = self.registers[rd_register];
                                                                break :blk3 source_value >> uimm_value;
                                                            },
                                                        }
                                                    };
                                                    self.set_register(rd_register, new_value);
                                                    break :blk2 .{ .srli = {} };
                                                },
                                                .srai => {
                                                    const rd_register = 8 + ((instruction >> 7) & 0b111);
                                                    const new_value = blk3: {
                                                        switch (cpu_kind) {
                                                            .rv32 => {
                                                                const uimm_value = ci_uimm_5(instruction);
                                                                const source_value: IRegister = @bitCast(self.registers[rd_register]);
                                                                break :blk3 source_value >> uimm_value;
                                                            },
                                                            .rv64 => {
                                                                const uimm_value = ci_uimm_6(instruction);
                                                                const source_value: IRegister = @bitCast(self.registers[rd_register]);
                                                                break :blk3 source_value >> uimm_value;
                                                            },
                                                        }
                                                    };
                                                    self.set_register(rd_register, @intCast(new_value));
                                                    break :blk2 .{ .srai = {} };
                                                },
                                                .andi => return error.NotImplemented,
                                                .sub_and => {
                                                    const bits_6_to_5: u2 = @intCast((instruction >> 5) & 0b11);
                                                    if (std.meta.intToEnum(Instruction01SsasSubandKind, bits_6_to_5)) |inst01_ssas_suband_kind| {
                                                        switch (inst01_ssas_suband_kind) {
                                                            .sub => {
                                                                const rd_register = 8 + ((instruction >> 7) & 0b111);
                                                                const rs2_register = 8 + ((instruction >> 2) & 0b111);
                                                                const source_value = self.registers[rd_register];
                                                                const new_value = @subWithOverflow(source_value, self.registers[rs2_register])[0];
                                                                self.set_register(rd_register, new_value);
                                                            },
                                                            .and_ => {
                                                                const rd_register = 8 + ((instruction >> 7) & 0b111);
                                                                const rs2_register = 8 + ((instruction >> 2) & 0b111);
                                                                const source_value = self.registers[rd_register];
                                                                const new_value = source_value & self.registers[rs2_register];
                                                                self.set_register(rd_register, new_value);
                                                            },
                                                        }
                                                        break :blk2 .{ .sub_and = inst01_ssas_suband_kind };
                                                    } else |_| {
                                                        return error.InvalidInstruction01SsasSubandKind;
                                                    }
                                                },
                                            }
                                        };
                                        self.pc += instruction_size;
                                        break :blk .{ .ssas = inst01_ssas };
                                    } else |_| {
                                        return error.InvalidInstruction01SsasKind;
                                    }
                                },
                                .beqz => {
                                    const source_register = 8 + ((instruction >> 7) & 0b111);
                                    const offset = cb_imm(instruction);
                                    if (self.registers[source_register] == 0) {
                                        self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + offset);
                                    } else {
                                        self.pc += instruction_size;
                                    }
                                    break :blk .{ .beqz = {} };
                                },
                                .bnez => {
                                    const source_register = 8 + ((instruction >> 7) & 0b111);
                                    const offset = cb_imm(instruction);
                                    if (self.registers[source_register] != 0) {
                                        self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + offset);
                                    } else {
                                        self.pc += instruction_size;
                                    }
                                    break :blk .{ .bnez = {} };
                                },
                            }
                        };
                        return .{ .cont = .{ .inst01 = inst01 } };
                    } else |_| {
                        return error.InvalidInstruction01Kind;
                    }
                },
                .inst10 => {
                    const instruction_size = @sizeOf(u16);
                    const instruction = std.mem.littleToNative(u16, std.mem.bytesToValue(u16, mem[self.pc .. self.pc + instruction_size]));
                    if (std.meta.intToEnum(Instruction10Kind, funct3_16(instruction))) |inst10_kind| {
                        const inst10: Instruction10 = blk: {
                            switch (inst10_kind) {
                                .jr_add => {
                                    const bit_12 = (instruction >> 12) & 0b1;
                                    if (bit_12 == 0) {
                                        // jr
                                        const source_register = rs1_16(instruction);
                                        self.pc = self.registers[source_register];
                                        break :blk .{ .jr_add = .jr };
                                    } else {
                                        // add
                                        const rd_register = rd_16(instruction);
                                        const rs2_register = rs2_16(instruction);
                                        const source_value = self.registers[rd_register];
                                        const new_value = @addWithOverflow(source_value, self.registers[rs2_register])[0];
                                        self.set_register(rd_register, new_value);
                                        self.pc += instruction_size;
                                        break :blk .{ .jr_add = .add };
                                    }
                                },
                                .sdsp => {
                                    if (cpu_kind != .rv64) {
                                        return error.RV64OnlyInstruction;
                                    }
                                    const sp = self.registers[2];
                                    const offset = css_uimm_6(instruction);
                                    const rs2_register = rs2_16(instruction);
                                    const rs2_value = self.registers[rs2_register];
                                    const dest_address = sp + offset;
                                    @memcpy(mem[dest_address .. dest_address + 8], &std.mem.toBytes(rs2_value));
                                    self.pc += instruction_size;
                                    break :blk .{ .sdsp = {} };
                                },
                            }
                        };
                        return .{ .cont = .{ .inst10 = inst10 } };
                    } else |_| {
                        return error.InvalidInstruction10Kind;
                    }
                },
                .inst11 => {
                    const instruction_size = @sizeOf(u32);
                    const instruction = std.mem.littleToNative(u32, std.mem.bytesToValue(u32, mem[self.pc .. self.pc + instruction_size]));
                    if (std.meta.intToEnum(Instruction11Kind, opcode_32(instruction))) |inst11_kind| {
                        switch (inst11_kind) {
                            .op => {
                                if (std.meta.intToEnum(Instruction11OpKind, funct7_32(instruction))) |inst11_op_kind| {
                                    const inst11_op: Instruction11Op = blk: {
                                        switch (inst11_op_kind) {
                                            .add => {
                                                const source1_register = rs1_32(instruction);
                                                const source1_value = self.registers[source1_register];
                                                const source2_register = rs2_32(instruction);
                                                const source2_value = self.registers[source2_register];
                                                const dest_register = rd_32(instruction);
                                                const new_value = @addWithOverflow(source1_value, source2_value)[0];
                                                self.set_register(dest_register, new_value);
                                                break :blk .{ .add = {} };
                                            },
                                            .sub => {
                                                const source1_register = rs1_32(instruction);
                                                const source1_value = self.registers[source1_register];
                                                const source2_register = rs2_32(instruction);
                                                const source2_value = self.registers[source2_register];
                                                const dest_register = rd_32(instruction);
                                                const new_value = @subWithOverflow(source1_value, source2_value)[0];
                                                self.set_register(dest_register, new_value);
                                                break :blk .{ .sub = {} };
                                            },
                                            .m_ext => {
                                                const bits_14_to_12: u3 = @intCast((instruction >> 12) & 0b111);
                                                if (std.meta.intToEnum(Instruction11OpMextKind, bits_14_to_12)) |inst11_op_mext_kind| {
                                                    switch (inst11_op_mext_kind) {
                                                        .mul => {
                                                            const source1_register = rs1_32(instruction);
                                                            const source1_value: IRegister = @bitCast(self.registers[source1_register]);
                                                            const source2_register = rs2_32(instruction);
                                                            const source2_value: IRegister = @bitCast(self.registers[source2_register]);
                                                            const dest_register = rd_32(instruction);
                                                            const new_value = @mulWithOverflow(source1_value, source2_value)[0];
                                                            self.set_register(dest_register, @bitCast(new_value));
                                                        },
                                                        .divu => {
                                                            const source1_register = rs1_32(instruction);
                                                            const source1_value = self.registers[source1_register];
                                                            const source2_register = rs2_32(instruction);
                                                            const source2_value = self.registers[source2_register];
                                                            const dest_register = rd_32(instruction);
                                                            const new_value = source1_value / source2_value;
                                                            self.set_register(dest_register, new_value);
                                                        },
                                                        .mulhu => {
                                                            const source1_register = rs1_32(instruction);
                                                            const source1_value: URegisterDouble = self.registers[source1_register];
                                                            const source2_register = rs2_32(instruction);
                                                            const source2_value: URegisterDouble = self.registers[source2_register];
                                                            const dest_register = rd_32(instruction);
                                                            const new_value = (source1_value * source2_value) >> @bitSizeOf(URegister);
                                                            self.set_register(dest_register, @intCast(new_value));
                                                        },
                                                    }
                                                    break :blk .{ .m_ext = inst11_op_mext_kind };
                                                } else |_| {
                                                    return error.InvalidInstruction11OpMextKind;
                                                }
                                            },
                                        }
                                    };
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .op = inst11_op } } };
                                } else |_| {
                                    return error.InvalidInstruction11OpKind;
                                }
                            },
                            .op_imm => {
                                if (std.meta.intToEnum(Instruction11OpImmKind, funct3_32(instruction))) |inst11_op_imm_kind| {
                                    switch (inst11_op_imm_kind) {
                                        .addi => {
                                            const source_register = rs1_32(instruction);
                                            const dest_register = rd_32(instruction);
                                            const imm_value = i_imm_32(instruction);
                                            const source_value: IRegister = @bitCast(self.registers[source_register]);
                                            const new_value = source_value + imm_value;
                                            self.set_register(dest_register, @bitCast(new_value));
                                        },
                                        .slli => {
                                            const source_register = rs1_32(instruction);
                                            const dest_register = rd_32(instruction);
                                            const new_value = blk: {
                                                switch (cpu_kind) {
                                                    .rv32 => {
                                                        const imm_value = i_uimm_5(instruction);
                                                        const source_value = self.registers[source_register];
                                                        break :blk source_value << imm_value;
                                                    },
                                                    .rv64 => {
                                                        const imm_value = i_uimm_6(instruction);
                                                        const source_value = self.registers[source_register];
                                                        break :blk source_value << imm_value;
                                                    },
                                                }
                                            };
                                            self.set_register(dest_register, @bitCast(new_value));
                                        },
                                        .sltiu => {
                                            const source_register = rs1_32(instruction);
                                            const dest_register = rd_32(instruction);
                                            const imm_value = i_imm_32(instruction);
                                            const source_value: IRegister = @bitCast(self.registers[source_register]);
                                            const new_value: u32 = if (source_value < imm_value) 1 else 0;
                                            self.set_register(dest_register, new_value);
                                        },
                                        .andi => {
                                            const source_register = rs1_32(instruction);
                                            const dest_register = rd_32(instruction);
                                            const imm_value = i_imm_32(instruction);
                                            const source_value: IRegister = @bitCast(self.registers[source_register]);
                                            const new_value = source_value & imm_value;
                                            self.set_register(dest_register, @bitCast(new_value));
                                        },
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .op_imm = inst11_op_imm_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11OpImmKind;
                                }
                            },
                            .jal => {
                                const dest_register = rd_32(instruction);
                                const imm_value = j_imm_32(instruction);
                                const new_pc: URegister = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                self.set_register(dest_register, self.pc + instruction_size);
                                self.pc = new_pc;
                                return .{ .cont = .{ .inst11 = .{ .jal = {} } } };
                            },
                            .jalr => {
                                const source_register = rs1_32(instruction);
                                const source_value: IRegister = @bitCast(self.registers[source_register]);
                                const dest_register = rd_32(instruction);
                                const imm_value = i_imm_32(instruction);
                                const new_pc = @as(URegister, @intCast(source_value + imm_value)) & ~@as(URegister, 1);
                                self.set_register(dest_register, self.pc + instruction_size);
                                self.pc = new_pc;
                                return .{ .cont = .{ .inst11 = .{ .jalr = {} } } };
                            },
                            .lui => {
                                const dest_register = rd_32(instruction);
                                const imm_value = u_uimm_32(instruction);
                                self.set_register(dest_register, imm_value);
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst11 = .{ .lui = {} } } };
                            },
                            .auipc => return error.NotImplemented,
                            .branch => {
                                const source1_register = rs1_32(instruction);
                                const source2_register = rs2_32(instruction);
                                const offset = b_imm_32(instruction);
                                if (std.meta.intToEnum(Instruction11BranchKind, funct3_32(instruction))) |inst11_branch_kind| {
                                    const cond = switch (inst11_branch_kind) {
                                        .beq => @as(IRegister, @bitCast(self.registers[source1_register])) == @as(IRegister, @bitCast(self.registers[source2_register])),
                                        .bne => @as(IRegister, @bitCast(self.registers[source1_register])) != @as(IRegister, @bitCast(self.registers[source2_register])),
                                        .blt => @as(IRegister, @bitCast(self.registers[source1_register])) < @as(IRegister, @bitCast(self.registers[source2_register])),
                                        .bge => @as(IRegister, @bitCast(self.registers[source1_register])) >= @as(IRegister, @bitCast(self.registers[source2_register])),
                                        .bltu => self.registers[source1_register] < self.registers[source2_register],
                                        .bgeu => self.registers[source1_register] >= self.registers[source2_register],
                                    };
                                    if (cond) {
                                        self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + offset);
                                    } else {
                                        self.pc += instruction_size;
                                    }
                                    return .{ .cont = .{ .inst11 = .{ .branch = inst11_branch_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11BranchKind;
                                }
                            },
                            .load => {
                                const source_register = rs1_32(instruction);
                                const offset = i_imm_32(instruction);
                                const dest_register = rd_32(instruction);
                                const source_address: URegister = @intCast(@as(IRegister, @intCast(self.registers[source_register])) + offset);
                                if (std.meta.intToEnum(Instruction11LoadKind, funct3_32(instruction))) |inst11_load_kind| {
                                    switch (inst11_load_kind) {
                                        .lb => self.set_register(dest_register, @intCast(@as(i8, @intCast(mem[source_address])))),
                                        .lh => self.set_register(dest_register, @intCast(std.mem.bytesToValue(i16, mem[source_address .. source_address + 2]))),
                                        .lw => self.set_register(dest_register, @intCast(std.mem.bytesToValue(i32, mem[source_address .. source_address + 4]))),
                                        .lbu => self.set_register(dest_register, @as(u8, @intCast(mem[source_address]))),
                                        .lhu => self.set_register(dest_register, std.mem.bytesToValue(u16, mem[source_address .. source_address + 2])),
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .load = inst11_load_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11LoadKind;
                                }
                            },
                            .store => {
                                const dest_register = rs1_32(instruction);
                                const offset = s_imm_32(instruction);
                                const dest_address: URegister = @intCast(@as(IRegister, @intCast(self.registers[dest_register])) + offset);
                                const source_value = self.registers[rs2_32(instruction)];
                                if (std.meta.intToEnum(Instruction11StoreKind, funct3_32(instruction))) |inst11_store_kind| {
                                    switch (inst11_store_kind) {
                                        .sb => mem[dest_address] = @intCast(source_value),
                                        .sh => {
                                            const val: u16 = @intCast(source_value);
                                            @memcpy(mem[dest_address .. dest_address + 2], &std.mem.toBytes(val));
                                        },
                                        .sw => {
                                            const val: u32 = @intCast(source_value);
                                            @memcpy(mem[dest_address .. dest_address + 4], &std.mem.toBytes(val));
                                        },
                                        .sd => {
                                            if (cpu_kind != .rv64) {
                                                return error.RV64OnlyInstruction;
                                            }
                                            @memcpy(mem[dest_address .. dest_address + 8], &std.mem.toBytes(source_value));
                                        },
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .store = inst11_store_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11StoreKind;
                                }
                            },
                            .fence => return error.NotImplemented,
                            .system => {
                                if (std.meta.intToEnum(Instruction11SystemKind, funct3_32(instruction))) |inst11_system_kind| {
                                    switch (inst11_system_kind) {
                                        .ecall_ebreak => {
                                            switch (i_imm_32(instruction)) {
                                                // ecall
                                                0 => {
                                                    self.pc += instruction_size;
                                                    return .{ .system = self.registers[10] };
                                                },
                                                // ebreak
                                                1 => {
                                                    return error.NotImplemented;
                                                },
                                                else => return error.InvalidParameter,
                                            }
                                        },
                                        .csrrw => {
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
                                        .csrrs => {
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
                                        .csrrc => {
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
                                        .csrrwi => {
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
                                        .csrrsi => {
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
                                        .csrrci => {
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
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .system = inst11_system_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11SystemKind;
                                }
                            },
                            .rv64i => {
                                const bits_14_to_12: u3 = @intCast((instruction >> 12) & 0b111);
                                if (std.meta.intToEnum(Instruction11RV64IKind, bits_14_to_12)) |inst11_rv64i_kind| {
                                    switch (inst11_rv64i_kind) {
                                        .addiw => {
                                            const source_register = rs1_32(instruction);
                                            const dest_register = rd_32(instruction);
                                            const imm_value = i_imm_32(instruction);
                                            const source_value: IRegister = @bitCast(self.registers[source_register]);
                                            const new_value = @addWithOverflow(source_value, imm_value)[0];
                                            self.set_register(dest_register, @bitCast(new_value));
                                        },
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .rv64i = inst11_rv64i_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11RV64IKind;
                                }
                            },
                        }
                    } else |_| {
                        return error.InvalidInstruction11Kind;
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

pub const InstructionKind = enum(u2) {
    inst00 = 0b00,
    inst01 = 0b01,
    inst10 = 0b10,
    inst11 = 0b11,
};
pub const Instruction = union(InstructionKind) {
    inst00: Instruction00,
    inst01: Instruction01,
    inst10: Instruction10,
    inst11: Instruction11,
};
pub const Instruction00Kind = enum(u3) {
    addi4spn,
};
pub const Instruction00 = union(Instruction00Kind) {
    addi4spn,
};
pub const Instruction01Kind = enum(u3) {
    addi = 0b000,
    jal = 0b001,
    li = 0b010,
    ssas = 0b100,
    beqz = 0b110,
    bnez = 0b111,
};
pub const Instruction01 = union(Instruction01Kind) {
    addi,
    jal,
    li,
    ssas: Instruction01Ssas,
    beqz,
    bnez,
};
pub const Instruction01SsasKind = enum(u2) {
    srli = 0b00,
    srai = 0b01,
    andi = 0b10,
    sub_and = 0b11,
};
pub const Instruction01Ssas = union(Instruction01SsasKind) {
    srli,
    srai,
    andi,
    sub_and: Instruction01SsasSubandKind,
};
pub const Instruction01SsasSubandKind = enum(u2) {
    sub = 0b00,
    and_ = 0b11,
};
pub const Instruction10Kind = enum(u3) {
    jr_add = 0b100,
    sdsp = 0b111,
};
pub const Instruction10 = union(Instruction10Kind) {
    jr_add: Instruction10JraddKind,
    sdsp,
};
pub const Instruction10JraddKind = enum {
    jr,
    add,
};
pub const Instruction11Kind = enum(u7) {
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
    rv64i = 0b00110_11,
};
pub const Instruction11 = union(Instruction11Kind) {
    op: Instruction11Op,
    op_imm: Instruction11OpImmKind,
    jal,
    jalr,
    lui,
    auipc,
    branch: Instruction11BranchKind,
    load: Instruction11LoadKind,
    store: Instruction11StoreKind,
    fence,
    system: Instruction11SystemKind,
    rv64i: Instruction11RV64IKind,
};
pub const Instruction11OpKind = enum(u7) {
    add = 0b00000_00,
    sub = 0b01000_00,
    m_ext = 0b00000_01,
};
pub const Instruction11Op = union(Instruction11OpKind) {
    add,
    sub,
    m_ext: Instruction11OpMextKind,
};
pub const Instruction11OpMextKind = enum(u3) {
    mul = 0b000,
    divu = 0b101,
    mulhu = 0b011,
};
pub const Instruction11OpImmKind = enum(u3) {
    addi = 0b000,
    slli = 0b001,
    sltiu = 0b011,
    andi = 0b111,
};
pub const Instruction11BranchKind = enum(u3) {
    beq = 0b000,
    bne = 0b001,
    blt = 0b100,
    bge = 0b101,
    bltu = 0b110,
    bgeu = 0b111,
};
pub const Instruction11LoadKind = enum(u3) {
    lb = 0b000,
    lh = 0b001,
    lw = 0b010,
    lbu = 0b100,
    lhu = 0b101,
};
pub const Instruction11StoreKind = enum(u3) {
    sb = 0b000,
    sh = 0b001,
    sw = 0b010,
    sd = 0b011,
};
pub const Instruction11SystemKind = enum(u3) {
    ecall_ebreak = 0b000,
    csrrw = 0b001,
    csrrs = 0b010,
    csrrc = 0b011,
    csrrwi = 0b101,
    csrrsi = 0b110,
    csrrci = 0b111,
};
pub const Instruction11RV64IKind = enum(u3) {
    addiw = 0b000,
};

const SIGN_BIT_32: u32 = 0b1000_0000_0000_0000_0000_0000_0000_0000;
const SIGN_BIT_16: u32 = 0b1000_0000_0000_0000;
const C_20_BITS: u32 = 0b1111_1111_1111_1111_1111;
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

fn opcode_32(instruction: u32) u7 {
    return @intCast(extract_32(instruction, 0, C_7_BITS));
}

fn rd_32(instruction: u32) u5 {
    return @intCast(extract_32(instruction, 7, C_5_BITS));
}

fn rd_16(instruction: u16) u5 {
    return @intCast(extract_16(instruction, 7, C_5_BITS));
}

fn rs1_32(instruction: u32) u5 {
    return @intCast(extract_32(instruction, 15, C_5_BITS));
}

fn rs1_16(instruction: u16) u5 {
    return @intCast(extract_16(instruction, 7, C_5_BITS));
}

fn rs2_32(instruction: u32) u5 {
    return @intCast(extract_32(instruction, 20, C_5_BITS));
}

fn rs2_16(instruction: u16) u5 {
    return @intCast(extract_16(instruction, 2, C_5_BITS));
}

fn funct3_16(instruction: u16) u3 {
    return @intCast(extract_16(instruction, 13, C_3_BITS));
}

fn funct3_32(instruction: u32) u3 {
    return @intCast(extract_32(instruction, 12, C_3_BITS));
}

fn funct7_32(instruction: u32) u7 {
    return @intCast(extract_32(instruction, 25, C_7_BITS));
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

fn sign_extend_16(raw_value: u16, bits: u4, sign_bit: bool) i16 {
    const bit_mask = (@as(u16, 1) << bits) - 1;
    const sign_mask = ~bit_mask;
    const extension = if (sign_bit) sign_mask else 0;
    return @bitCast((raw_value & bit_mask) | extension);
}

fn i_imm_32(instruction: u32) i32 {
    const sign_bit = extract_32(instruction, 0, SIGN_BIT_32) != 0;
    const raw_value = extract_32(instruction, 20, C_11_BITS);
    return sign_extend_32(raw_value, 11, sign_bit);
}

fn i_uimm_5(instruction: u32) u5 {
    return @intCast(extract_32(instruction, 20, C_5_BITS));
}

fn i_uimm_6(instruction: u32) u6 {
    return @intCast(extract_32(instruction, 20, C_6_BITS));
}

fn s_imm_32(instruction: u32) i32 {
    const sign_bit = extract_32(instruction, 0, SIGN_BIT_32) != 0;
    const upper_6_bits = extract_32(instruction, 25, C_6_BITS) << 5;
    const lower_5_bits = extract_32(instruction, 7, C_5_BITS);
    return sign_extend_32(upper_6_bits | lower_5_bits, 11, sign_bit);
}

fn b_imm_32(instruction: u32) i32 {
    const sign_bit = extract_32(instruction, 0, SIGN_BIT_32) != 0;
    const bit_11 = extract_32(instruction, 7, 0b1) << 11;
    const bits_10_to_5 = extract_32(instruction, 25, C_6_BITS) << 5;
    const bits_4_to_1 = extract_32(instruction, 8, C_4_BITS) << 1;
    return sign_extend_32(bit_11 | bits_10_to_5 | bits_4_to_1, 12, sign_bit);
}

fn j_imm_32(instruction: u32) i32 {
    const sign_bit = extract_32(instruction, 0, SIGN_BIT_32) != 0;
    const bit_11 = extract_32(instruction, 20, 0b1) << 11;
    const bits_10_to_1 = extract_32(instruction, 21, C_10_BITS) << 1;
    const bits_19_to_12 = extract_32(instruction, 12, C_8_BITS) << 12;
    return sign_extend_32(bits_19_to_12 | bit_11 | bits_10_to_1, 20, sign_bit);
}

fn u_uimm_32(instruction: u32) u32 {
    return extract_32(instruction, 12, C_20_BITS) << 12;
}

fn ci_imm(instruction: u16) i16 {
    const sign_bit = extract_16(instruction, 11, 0b1) != 0;
    const bits_4_to_0 = extract_16(instruction, 2, C_5_BITS);
    return sign_extend_16(bits_4_to_0, 5, sign_bit);
}

fn ci_uimm_5(instruction: u16) u5 {
    const bits_4_to_0 = extract_16(instruction, 2, C_5_BITS);
    return @intCast(bits_4_to_0);
}

fn ci_uimm_6(instruction: u16) u6 {
    const bit_5 = extract_16(instruction, 11, 0b1) << 5;
    const bits_4_to_0 = extract_16(instruction, 2, C_5_BITS);
    return @intCast(bit_5 | bits_4_to_0);
}

fn cj_imm(instruction: u16) i16 {
    const sign_bit = extract_16(instruction, 12, 0b1) != 0;
    const bits_10_to_1 = extract_16(instruction, 2, C_10_BITS) << 1;
    return sign_extend_16(bits_10_to_1, 11, sign_bit);
}

fn cb_imm(instruction: u16) i16 {
    const sign_bit = extract_16(instruction, 12, 0b1) != 0;
    const bits_7_to_6 = extract_16(instruction, 10, 0b11) << 6;
    const bit_5 = extract_16(instruction, 2, 0b1) << 5;
    const bits_4_to_1 = extract_16(instruction, 3, C_4_BITS) << 1;
    return sign_extend_16(bits_7_to_6 | bit_5 | bits_4_to_1, 8, sign_bit);
}

fn css_uimm_6(instruction: u16) u6 {
    return @intCast(extract_16(instruction, 7, C_6_BITS));
}

fn ciw_uimm_8(instruction: u16) u8 {
    return @intCast(extract_16(instruction, 5, C_8_BITS));
}
