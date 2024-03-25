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
                .inst48 => {
                    return error.NotImplemented;
                },
                .inst16a => {
                    const instruction_size = @sizeOf(u16);
                    const instruction = std.mem.littleToNative(u16, std.mem.bytesToValue(u16, mem[self.pc .. self.pc + instruction_size]));
                    if (std.meta.intToEnum(Instruction16AKind, funct3_16(instruction))) |inst16a_kind| {
                        const inst16a: Instruction16A = blk: {
                            switch (inst16a_kind) {
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
                                    if (std.meta.intToEnum(Instruction16ASsasKind, bits_11_to_10)) |inst16a_ssas_kind| {
                                        const inst16a_ssas: Instruction16ASsas = blk2: {
                                            switch (inst16a_ssas_kind) {
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
                                                    if (std.meta.intToEnum(Instruction16ASsasSubandKind, bits_6_to_5)) |inst16a_ssas_suband_kind| {
                                                        switch (inst16a_ssas_suband_kind) {
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
                                                        break :blk2 .{ .sub_and = inst16a_ssas_suband_kind };
                                                    } else |_| {
                                                        return error.InvalidInstruction16ASsasSubandKind;
                                                    }
                                                },
                                            }
                                        };
                                        self.pc += instruction_size;
                                        break :blk .{ .ssas = inst16a_ssas };
                                    } else |_| {
                                        return error.InvalidInstruction16ASsasKind;
                                    }
                                },
                                .beqz => {
                                    const source_register = (instruction >> 7) & 0b111;
                                    const offset = cb_imm(instruction);
                                    if (self.registers[source_register] == 0) {
                                        self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + offset);
                                    } else {
                                        self.pc += instruction_size;
                                    }
                                    break :blk .{ .beqz = {} };
                                },
                            }
                        };
                        return .{ .cont = .{ .inst16a = inst16a } };
                    } else |_| {
                        return error.InvalidInstruction16AKind;
                    }
                },
                .inst16b => {
                    const instruction_size = @sizeOf(u16);
                    const instruction = std.mem.littleToNative(u16, std.mem.bytesToValue(u16, mem[self.pc .. self.pc + instruction_size]));
                    if (std.meta.intToEnum(Instruction16BKind, funct3_16(instruction))) |inst16b_kind| {
                        const inst16b: Instruction16B = blk: {
                            switch (inst16b_kind) {
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
                            }
                        };
                        return .{ .cont = .{ .inst16b = inst16b } };
                    } else |_| {
                        return error.InvalidInstruction16BKind;
                    }
                },
                .inst32 => {
                    const instruction_size = @sizeOf(u32);
                    const instruction = std.mem.littleToNative(u32, std.mem.bytesToValue(u32, mem[self.pc .. self.pc + instruction_size]));
                    if (std.meta.intToEnum(Instruction32Kind, opcode_32(instruction))) |inst32_kind| {
                        switch (inst32_kind) {
                            .op => {
                                if (std.meta.intToEnum(Instruction32OpKind, funct7_32(instruction))) |inst32_op_kind| {
                                    const inst32_op: Instruction32Op = blk: {
                                        switch (inst32_op_kind) {
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
                                                if (std.meta.intToEnum(Instruction32OpMextKind, bits_14_to_12)) |inst32_op_mext_kind| {
                                                    switch (inst32_op_mext_kind) {
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
                                                    break :blk .{ .m_ext = inst32_op_mext_kind };
                                                } else |_| {
                                                    return error.InvalidInstruction32OpMextKind;
                                                }
                                            },
                                        }
                                    };
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst32 = .{ .op = inst32_op } } };
                                } else |_| {
                                    return error.InvalidInstruction32OpKind;
                                }
                            },
                            .op_imm => {
                                if (std.meta.intToEnum(Instruction32OpImmKind, funct3_32(instruction))) |inst32_op_imm_kind| {
                                    switch (inst32_op_imm_kind) {
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
                                    return .{ .cont = .{ .inst32 = .{ .op_imm = inst32_op_imm_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction32OpImmKind;
                                }
                            },
                            .jal => {
                                const dest_register = rd_32(instruction);
                                const imm_value = j_imm_32(instruction);
                                const new_pc: URegister = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                self.set_register(dest_register, self.pc + instruction_size);
                                self.pc = new_pc;
                                return .{ .cont = .{ .inst32 = .{ .jal = {} } } };
                            },
                            .jalr => {
                                const source_register = rs1_32(instruction);
                                const source_value: IRegister = @bitCast(self.registers[source_register]);
                                const dest_register = rd_32(instruction);
                                const imm_value = i_imm_32(instruction);
                                const new_pc = @as(URegister, @intCast(source_value + imm_value)) & ~@as(URegister, 1);
                                self.set_register(dest_register, self.pc + instruction_size);
                                self.pc = new_pc;
                                return .{ .cont = .{ .inst32 = .{ .jalr = {} } } };
                            },
                            .lui => {
                                const dest_register = rd_32(instruction);
                                const imm_value: URegister = u_uimm_32(instruction);
                                self.set_register(dest_register, imm_value);
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst32 = .{ .lui = {} } } };
                            },
                            .auipc => return error.NotImplemented,
                            .branch => {
                                const source1_register = rs1_32(instruction);
                                const source2_register = rs2_32(instruction);
                                const offset = b_imm_32(instruction);
                                if (std.meta.intToEnum(Instruction32BranchKind, funct3_32(instruction))) |inst32_branch_kind| {
                                    const cond = switch (inst32_branch_kind) {
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
                                    return .{ .cont = .{ .inst32 = .{ .branch = inst32_branch_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction32BranchKind;
                                }
                            },
                            .load => {
                                const source_register = rs1_32(instruction);
                                const offset = i_imm_32(instruction);
                                const dest_register = rd_32(instruction);
                                const source_address: URegister = @intCast(@as(IRegister, @intCast(self.registers[source_register])) + offset);
                                if (std.meta.intToEnum(Instruction32LoadKind, funct3_32(instruction))) |inst32_load_kind| {
                                    switch (inst32_load_kind) {
                                        .lb => self.set_register(dest_register, @intCast(@as(i8, @intCast(mem[source_address])))),
                                        .lh => self.set_register(dest_register, @intCast(std.mem.bytesToValue(i16, mem[source_address .. source_address + 2]))),
                                        .lw => self.set_register(dest_register, @intCast(std.mem.bytesToValue(i32, mem[source_address .. source_address + 4]))),
                                        .lbu => self.set_register(dest_register, @as(u8, @intCast(mem[source_address]))),
                                        .lhu => self.set_register(dest_register, std.mem.bytesToValue(u16, mem[source_address .. source_address + 2])),
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst32 = .{ .load = inst32_load_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction32LoadKind;
                                }
                            },
                            .store => {
                                const dest_register = rs1_32(instruction);
                                const offset = s_imm_32(instruction);
                                const dest_address: URegister = @intCast(@as(IRegister, @intCast(self.registers[dest_register])) + offset);
                                const source_value = self.registers[rs2_32(instruction)];
                                if (std.meta.intToEnum(Instruction32StoreKind, funct3_32(instruction))) |inst32_store_kind| {
                                    switch (inst32_store_kind) {
                                        .sb => mem[dest_address] = @intCast(source_value),
                                        .sh => {
                                            const val: u16 = @intCast(source_value);
                                            @memcpy(mem[dest_address .. dest_address + 2], &std.mem.toBytes(val));
                                        },
                                        .sw => {
                                            const val: u32 = @intCast(source_value);
                                            @memcpy(mem[dest_address .. dest_address + 4], &std.mem.toBytes(val));
                                        },
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst32 = .{ .store = inst32_store_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction32StoreKind;
                                }
                            },
                            .fence => return error.NotImplemented,
                            .system => {
                                if (std.meta.intToEnum(Instruction32SystemKind, funct3_32(instruction))) |inst32_system_kind| {
                                    switch (inst32_system_kind) {
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
                                    return .{ .cont = .{ .inst32 = .{ .system = inst32_system_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction32SystemKind;
                                }
                            },
                            .rv64i => {
                                const bits_14_to_12: u3 = @intCast((instruction >> 12) & 0b111);
                                if (std.meta.intToEnum(Instruction32RV64IKind, bits_14_to_12)) |inst32_rv64i_kind| {
                                    switch (inst32_rv64i_kind) {
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
                                    return .{ .cont = .{ .inst32 = .{ .rv64i = inst32_rv64i_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction32RV64IKind;
                                }
                            },
                        }
                    } else |_| {
                        return error.InvalidInstruction32Kind;
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
    inst48 = 0b00,
    inst16a = 0b01,
    inst16b = 0b10,
    inst32 = 0b11,
};
pub const Instruction = union(InstructionKind) {
    inst48,
    inst16a: Instruction16A,
    inst16b: Instruction16B,
    inst32: Instruction32,
};
pub const Instruction16AKind = enum(u3) {
    addi = 0b000,
    jal = 0b001,
    li = 0b010,
    ssas = 0b100,
    beqz = 0b110,
};
pub const Instruction16A = union(Instruction16AKind) {
    addi,
    jal,
    li,
    ssas: Instruction16ASsas,
    beqz,
};
pub const Instruction16ASsasKind = enum(u2) {
    srli = 0b00,
    srai = 0b01,
    andi = 0b10,
    sub_and = 0b11,
};
pub const Instruction16ASsas = union(Instruction16ASsasKind) {
    srli,
    srai,
    andi,
    sub_and: Instruction16ASsasSubandKind,
};
pub const Instruction16ASsasSubandKind = enum(u2) {
    sub = 0b00,
    and_ = 0b11,
};
pub const Instruction16BKind = enum(u3) {
    jr_add = 0b100,
};
pub const Instruction16B = union(Instruction16BKind) {
    jr_add: Instruction16BJraddKind,
};
pub const Instruction16BJraddKind = enum {
    jr,
    add,
};
pub const Instruction32Kind = enum(u7) {
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
pub const Instruction32 = union(Instruction32Kind) {
    op: Instruction32Op,
    op_imm: Instruction32OpImmKind,
    jal,
    jalr,
    lui,
    auipc,
    branch: Instruction32BranchKind,
    load: Instruction32LoadKind,
    store: Instruction32StoreKind,
    fence,
    system: Instruction32SystemKind,
    rv64i: Instruction32RV64IKind,
};
pub const Instruction32OpKind = enum(u7) {
    add = 0b00000_00,
    sub = 0b01000_00,
    m_ext = 0b00000_01,
};
pub const Instruction32Op = union(Instruction32OpKind) {
    add,
    sub,
    m_ext: Instruction32OpMextKind,
};
pub const Instruction32OpMextKind = enum(u3) {
    mul = 0b000,
    divu = 0b101,
    mulhu = 0b011,
};
pub const Instruction32OpImmKind = enum(u3) {
    addi = 0b000,
    slli = 0b001,
    sltiu = 0b011,
    andi = 0b111,
};
pub const Instruction32BranchKind = enum(u3) {
    beq = 0b000,
    bne = 0b001,
    blt = 0b100,
    bge = 0b101,
    bltu = 0b110,
    bgeu = 0b111,
};
pub const Instruction32LoadKind = enum(u3) {
    lb = 0b000,
    lh = 0b001,
    lw = 0b010,
    lbu = 0b100,
    lhu = 0b101,
};
pub const Instruction32StoreKind = enum(u3) {
    sb = 0b000,
    sh = 0b001,
    sw = 0b010,
};
pub const Instruction32SystemKind = enum(u3) {
    ecall_ebreak = 0b000,
    csrrw = 0b001,
    csrrs = 0b010,
    csrrc = 0b011,
    csrrwi = 0b101,
    csrrsi = 0b110,
    csrrci = 0b111,
};
pub const Instruction32RV64IKind = enum(u3) {
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

fn u_uimm_32(instruction: u32) u20 {
    return @intCast(extract_32(instruction, 12, C_20_BITS));
}

fn ci_imm(instruction: u16) i16 {
    const sign_bit = extract_16(instruction, 11, 0b1) != 0;
    const bits_4_to_0 = extract_16(instruction, 2, C_5_BITS);
    return sign_extend_16(bits_4_to_0, 6, sign_bit);
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
    return sign_extend_16(bits_10_to_1, 12, sign_bit);
}

fn cb_imm(instruction: u16) i16 {
    const sign_bit = extract_16(instruction, 8, 0b1) != 0;
    const bits_7_to_6 = extract_16(instruction, 10, 0b11);
    const bits_5_to_1 = extract_16(instruction, 2, C_5_BITS);
    return sign_extend_16(bits_7_to_6 | bits_5_to_1, 9, sign_bit);
}
