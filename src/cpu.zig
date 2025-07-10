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

            const next_byte: packed struct {
                kind: u2,
                rest: u6,
            } = @bitCast(mem[self.pc]);

            switch (@as(InstructionKind, @enumFromInt(next_byte.kind))) {
                .inst00 => {
                    const instruction_size = @sizeOf(u16);
                    const instruction_int = std.mem.readInt(u16, mem[self.pc..][0..instruction_size], .little);
                    const instruction: packed struct {
                        op: u2,
                        rest: u11,
                        kind: u3,
                    } = @bitCast(instruction_int);

                    //std.debug.print("{}\n", .{try std.meta.intToEnum(Instruction00Kind, instruction.kind)});
                    if (std.meta.intToEnum(Instruction00Kind, instruction.kind)) |inst00_kind| {
                        switch (inst00_kind) {
                            .addi4spn => {
                                const inst_parts: packed struct {
                                    rd: u3,
                                    imm_3: u1,
                                    imm_2: u1,
                                    imm_9_to_6: u4,
                                    imm_5_to_4: u2,
                                } = @bitCast(instruction.rest);
                                const Immediate = packed struct {
                                    rest: u2,
                                    imm_2: u1,
                                    imm_3: u1,
                                    imm_5_to_4: u2,
                                    imm_9_to_6: u4,
                                };
                                const imm_value: u10 = @bitCast(Immediate{
                                    .rest = 0,
                                    .imm_2 = inst_parts.imm_2,
                                    .imm_3 = inst_parts.imm_3,
                                    .imm_5_to_4 = inst_parts.imm_5_to_4,
                                    .imm_9_to_6 = inst_parts.imm_9_to_6,
                                });
                                const rd_register = 8 + @as(URegister, inst_parts.rd);
                                self.setRegister(rd_register, self.registers[2] + imm_value);
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst00 = .{ .addi4spn = {} } } };
                            },
                            .sw => {
                                const inst_parts: packed struct {
                                    rs2: u3,
                                    imm_6: u1,
                                    imm_2: u1,
                                    rs1: u3,
                                    imm_5_to_3: u3,
                                } = @bitCast(instruction.rest);
                                const Immediate = packed struct {
                                    rest: u2,
                                    imm_2: u1,
                                    imm_5_to_3: u3,
                                    imm_6: u1,
                                };
                                const imm_value: u7 = @bitCast(Immediate{
                                    .rest = 0,
                                    .imm_2 = inst_parts.imm_2,
                                    .imm_5_to_3 = inst_parts.imm_5_to_3,
                                    .imm_6 = inst_parts.imm_6,
                                });
                                const rs1_register = 8 + @as(URegister, inst_parts.rs1);
                                const rs2_register = 8 + @as(URegister, inst_parts.rs2);
                                const rs1_value = self.registers[rs1_register];
                                const rs2_value: u32 = @intCast(self.registers[rs2_register]);
                                const dest_address = rs1_value + imm_value;
                                @memcpy(mem[dest_address .. dest_address + 4], &std.mem.toBytes(rs2_value));
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst00 = .{ .sw = {} } } };
                            },
                        }
                    } else |_| {
                        return error.InvalidInstruction00Kind;
                    }
                    return error.NotImplemented;
                },
                .inst01 => {
                    const instruction_size = @sizeOf(u16);
                    const instruction_int = std.mem.readInt(u16, mem[self.pc..][0..instruction_size], .little);
                    const instruction: packed struct {
                        op: u2,
                        rest: u11,
                        kind: u3,
                    } = @bitCast(instruction_int);

                    //std.debug.print("{}\n", .{try std.meta.intToEnum(Instruction01Kind, instruction.kind)});
                    if (std.meta.intToEnum(Instruction01Kind, instruction.kind)) |inst01_kind| {
                        const inst01: Instruction01 = blk: {
                            switch (inst01_kind) {
                                .addi => {
                                    const inst_parts: packed struct {
                                        imm_4_to_0: u5,
                                        rd: u5,
                                        imm_5: u1,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        imm_4_to_0: u5,
                                        imm_5: u1,
                                    };
                                    const imm_value: i6 = @bitCast(Immediate{
                                        .imm_4_to_0 = inst_parts.imm_4_to_0,
                                        .imm_5 = inst_parts.imm_5,
                                    });
                                    const source_value: IRegister = @bitCast(self.registers[inst_parts.rd]);
                                    const new_value = source_value + imm_value;
                                    self.setRegister(inst_parts.rd, @bitCast(new_value));
                                    self.pc += instruction_size;
                                    break :blk .{ .addi = {} };
                                },
                                .jal => {
                                    const inst_parts: packed struct {
                                        imm_5: u1,
                                        imm_4_to_1: u4,
                                        imm_11_to_6: u6,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        rest: u1,
                                        imm_4_to_1: u4,
                                        imm_5: u1,
                                        imm_11_to_6: u6,
                                    };
                                    const imm_value: i12 = @bitCast(Immediate{
                                        .rest = 0,
                                        .imm_4_to_1 = inst_parts.imm_4_to_1,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_11_to_6 = inst_parts.imm_11_to_6,
                                    });
                                    const new_pc: URegister = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                    self.setRegister(1, self.pc + instruction_size);
                                    self.pc = new_pc;
                                    break :blk .{ .jal = {} };
                                },
                                .li => {
                                    const inst_parts: packed struct {
                                        imm_4_to_0: u5,
                                        rd: u5,
                                        imm_5: u1,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        imm_4_to_0: u5,
                                        imm_5: u1,
                                    };
                                    const imm_value: i6 = @bitCast(Immediate{
                                        .imm_4_to_0 = inst_parts.imm_4_to_0,
                                        .imm_5 = inst_parts.imm_5,
                                    });
                                    self.setRegister(inst_parts.rd, @intCast(imm_value));
                                    self.pc += instruction_size;
                                    break :blk .{ .li = {} };
                                },
                                .addi16sp_lui => {
                                    const inst_parts: packed struct {
                                        imm_4_to_0: u5,
                                        rd: u5,
                                        imm_5: u1,
                                    } = @bitCast(instruction.rest);
                                    switch (inst_parts.rd) {
                                        // addi16sp
                                        0b00010 => {
                                            const imm_parts: packed struct {
                                                imm_8_to_6: u3,
                                                imm_5: u1,
                                                imm_4: u1,
                                            } = @bitCast(inst_parts.imm_4_to_0);
                                            const Immediate = packed struct {
                                                rest: u4,
                                                imm_4: u1,
                                                imm_5: u1,
                                                imm_8_to_6: u3,
                                                imm_9: u1,
                                            };
                                            const imm_value: i10 = @bitCast(Immediate{
                                                .rest = 0,
                                                .imm_4 = imm_parts.imm_4,
                                                .imm_5 = imm_parts.imm_5,
                                                .imm_8_to_6 = imm_parts.imm_8_to_6,
                                                .imm_9 = inst_parts.imm_5,
                                            });
                                            self.setRegister(2, @bitCast(@as(IRegister, @bitCast(self.registers[2])) + imm_value));
                                            self.pc += instruction_size;
                                            break :blk .{ .addi16sp_lui = {} };
                                        },
                                        else => return error.NotImplemented,
                                    }
                                },
                                .ssas => {
                                    const inst_parts: packed struct {
                                        rest_4_to_0: u5,
                                        rd: u3,
                                        kind: u2,
                                        rest_5: u1,
                                    } = @bitCast(instruction.rest);
                                    if (std.meta.intToEnum(Instruction01SsasKind, inst_parts.kind)) |inst01_ssas_kind| {
                                        const inst01_ssas: Instruction01Ssas = blk2: {
                                            switch (inst01_ssas_kind) {
                                                .srli => {
                                                    const rd_register = 8 + @as(URegister, inst_parts.rd);
                                                    const new_value = blk3: {
                                                        switch (cpu_kind) {
                                                            .rv32 => {
                                                                const imm_value: u5 = inst_parts.rest_4_to_0;
                                                                const source_value = self.registers[rd_register];
                                                                break :blk3 source_value >> imm_value;
                                                            },
                                                            .rv64 => {
                                                                const Immediate = packed struct {
                                                                    imm_4_to_0: u5,
                                                                    imm_5: u1,
                                                                };
                                                                const imm_value: u6 = @bitCast(Immediate{
                                                                    .imm_4_to_0 = inst_parts.rest_4_to_0,
                                                                    .imm_5 = inst_parts.rest_5,
                                                                });
                                                                const source_value = self.registers[rd_register];
                                                                break :blk3 source_value >> imm_value;
                                                            },
                                                        }
                                                    };
                                                    self.setRegister(rd_register, new_value);
                                                    break :blk2 .{ .srli = {} };
                                                },
                                                .srai => {
                                                    const rd_register = 8 + @as(URegister, inst_parts.rd);
                                                    const new_value = blk3: {
                                                        switch (cpu_kind) {
                                                            .rv32 => {
                                                                const imm_value: u5 = inst_parts.rest_4_to_0;
                                                                const source_value: IRegister = @bitCast(self.registers[rd_register]);
                                                                break :blk3 source_value >> imm_value;
                                                            },
                                                            .rv64 => {
                                                                const Immediate = packed struct {
                                                                    imm_4_to_0: u5,
                                                                    imm_5: u1,
                                                                };
                                                                const imm_value: u6 = @bitCast(Immediate{
                                                                    .imm_4_to_0 = inst_parts.rest_4_to_0,
                                                                    .imm_5 = inst_parts.rest_5,
                                                                });
                                                                const source_value: IRegister = @bitCast(self.registers[rd_register]);
                                                                break :blk3 source_value >> imm_value;
                                                            },
                                                        }
                                                    };
                                                    self.setRegister(rd_register, @intCast(new_value));
                                                    break :blk2 .{ .srai = {} };
                                                },
                                                .andi => return error.NotImplemented,
                                                .sub_and => {
                                                    const rest_4_to_0_parts: packed struct {
                                                        rs2: u3,
                                                        kind: u2,
                                                    } = @bitCast(inst_parts.rest_4_to_0);
                                                    if (std.meta.intToEnum(Instruction01SsasSubandKind, rest_4_to_0_parts.kind)) |inst01_ssas_suband_kind| {
                                                        switch (inst01_ssas_suband_kind) {
                                                            .sub => {
                                                                const rd_register = 8 + @as(URegister, inst_parts.rd);
                                                                const rs2_register = 8 + @as(URegister, rest_4_to_0_parts.rs2);
                                                                const source_value = self.registers[rd_register];
                                                                const new_value = @subWithOverflow(source_value, self.registers[rs2_register])[0];
                                                                self.setRegister(rd_register, new_value);
                                                            },
                                                            .and_ => {
                                                                const rd_register = 8 + @as(URegister, inst_parts.rd);
                                                                const rs2_register = 8 + @as(URegister, rest_4_to_0_parts.rs2);
                                                                const source_value = self.registers[rd_register];
                                                                const new_value = source_value & self.registers[rs2_register];
                                                                self.setRegister(rd_register, new_value);
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
                                .j => {
                                    const inst_parts: packed struct {
                                        imm_5: u1,
                                        imm_4_to_1: u4,
                                        imm_11_to_6: u6,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        rest: u1,
                                        imm_4_to_1: u4,
                                        imm_5: u1,
                                        imm_11_to_6: u6,
                                    };
                                    const imm_value: i12 = @bitCast(Immediate{
                                        .rest = 0,
                                        .imm_4_to_1 = inst_parts.imm_4_to_1,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_11_to_6 = inst_parts.imm_11_to_6,
                                    });
                                    self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                    break :blk .{ .j = {} };
                                },
                                .beqz => {
                                    const inst_parts: packed struct {
                                        imm_5: u1,
                                        imm_4_to_1: u4,
                                        rs1: u3,
                                        imm_8_to_6: u3,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        rest: u1,
                                        imm_4_to_1: u4,
                                        imm_5: u1,
                                        imm_8_to_6: u3,
                                    };
                                    const imm_value: i9 = @bitCast(Immediate{
                                        .rest = 0,
                                        .imm_4_to_1 = inst_parts.imm_4_to_1,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_8_to_6 = inst_parts.imm_8_to_6,
                                    });
                                    const source_register = 8 + @as(URegister, inst_parts.rs1);
                                    if (self.registers[source_register] == 0) {
                                        self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                    } else {
                                        self.pc += instruction_size;
                                    }
                                    break :blk .{ .beqz = {} };
                                },
                                .bnez => {
                                    const inst_parts: packed struct {
                                        imm_5: u1,
                                        imm_4_to_1: u4,
                                        rs1: u3,
                                        imm_8_to_6: u3,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        rest: u1,
                                        imm_4_to_1: u4,
                                        imm_5: u1,
                                        imm_8_to_6: u3,
                                    };
                                    const imm_value: i9 = @bitCast(Immediate{
                                        .rest = 0,
                                        .imm_4_to_1 = inst_parts.imm_4_to_1,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_8_to_6 = inst_parts.imm_8_to_6,
                                    });
                                    const source_register = 8 + @as(URegister, inst_parts.rs1);
                                    if (self.registers[source_register] != 0) {
                                        self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
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
                    const instruction_int = std.mem.readInt(u16, mem[self.pc..][0..instruction_size], .little);
                    const instruction: packed struct {
                        op: u2,
                        rest: u11,
                        kind: u3,
                    } = @bitCast(instruction_int);

                    //std.debug.print("{}\n", .{try std.meta.intToEnum(Instruction10Kind, instruction.kind)});
                    if (std.meta.intToEnum(Instruction10Kind, instruction.kind)) |inst10_kind| {
                        const inst10: Instruction10 = blk: {
                            switch (inst10_kind) {
                                .ldsp => {
                                    if (cpu_kind != .rv64) {
                                        return error.RV64OnlyInstruction;
                                    }
                                    const inst_parts: packed struct {
                                        imm_8_to_6: u3,
                                        imm_4_to_3: u2,
                                        rd: u5,
                                        imm_5: u1,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        rest: u3,
                                        imm_4_to_3: u2,
                                        imm_5: u1,
                                        imm_8_to_6: u3,
                                    };
                                    const imm_value: u9 = @bitCast(Immediate{
                                        .rest = 0,
                                        .imm_4_to_3 = inst_parts.imm_4_to_3,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_8_to_6 = inst_parts.imm_8_to_6,
                                    });
                                    const sp = self.registers[2];
                                    const source_address = sp + imm_value;
                                    self.setRegister(inst_parts.rd, @bitCast(std.mem.readInt(URegister, mem[source_address..][0..8], .little)));
                                    self.pc += instruction_size;
                                    break :blk .{ .ldsp = {} };
                                },
                                .jr_add => {
                                    const inst_parts: packed struct {
                                        rs2: u5,
                                        rs1_or_rd: u5,
                                        kind: u1,
                                    } = @bitCast(instruction.rest);
                                    switch (inst_parts.kind) {
                                        // jr
                                        0 => {
                                            const rs1_register = inst_parts.rs1_or_rd;
                                            self.pc = self.registers[rs1_register];
                                            break :blk .{ .jr_add = .jr };
                                        },
                                        // add
                                        1 => {
                                            const rd_register = inst_parts.rs1_or_rd;
                                            const rs2_register = inst_parts.rs2;
                                            const source_value = self.registers[rd_register];
                                            const new_value = @addWithOverflow(source_value, self.registers[rs2_register])[0];
                                            self.setRegister(rd_register, new_value);
                                            self.pc += instruction_size;
                                            break :blk .{ .jr_add = .add };
                                        },
                                    }
                                },
                                .sdsp => {
                                    if (cpu_kind != .rv64) {
                                        return error.RV64OnlyInstruction;
                                    }
                                    const inst_parts: packed struct {
                                        rs2: u5,
                                        imm_8_to_6: u3,
                                        imm_5_to_3: u3,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        rest: u3,
                                        imm_5_to_3: u3,
                                        imm_8_to_6: u3,
                                    };
                                    const imm_value: u9 = @bitCast(Immediate{
                                        .rest = 0,
                                        .imm_5_to_3 = inst_parts.imm_5_to_3,
                                        .imm_8_to_6 = inst_parts.imm_8_to_6,
                                    });
                                    const sp = self.registers[2];
                                    const rs2_value = self.registers[inst_parts.rs2];
                                    const dest_address = sp + imm_value;
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
                    const instruction_int = std.mem.readInt(u32, mem[self.pc..][0..instruction_size], .little);
                    const instruction: packed struct {
                        op: u2,
                        kind: u5,
                        rest: u25,
                    } = @bitCast(instruction_int);

                    //std.debug.print("{}\n", .{try std.meta.intToEnum(Instruction11Kind, instruction.kind)});
                    if (std.meta.intToEnum(Instruction11Kind, instruction.kind)) |inst11_kind| {
                        switch (inst11_kind) {
                            .op => {
                                const inst_parts: packed struct {
                                    rest: u18,
                                    kind: u7,
                                } = @bitCast(instruction.rest);

                                if (std.meta.intToEnum(Instruction11OpKind, inst_parts.kind)) |inst11_op_kind| {
                                    const parts: packed struct {
                                        rd: u5,
                                        kind: u3,
                                        rs1: u5,
                                        rs2: u5,
                                    } = @bitCast(inst_parts.rest);

                                    const inst11_op: Instruction11Op = blk: {
                                        switch (inst11_op_kind) {
                                            .add => {
                                                const source1_value = self.registers[parts.rs1];
                                                const source2_value = self.registers[parts.rs2];
                                                const new_value = @addWithOverflow(source1_value, source2_value)[0];
                                                self.setRegister(parts.rd, new_value);
                                                break :blk .{ .add = {} };
                                            },
                                            .sub => {
                                                const source1_value = self.registers[parts.rs1];
                                                const source2_value = self.registers[parts.rs2];
                                                const new_value = @subWithOverflow(source1_value, source2_value)[0];
                                                self.setRegister(parts.rd, new_value);
                                                break :blk .{ .sub = {} };
                                            },
                                            .m_ext => {
                                                if (std.meta.intToEnum(Instruction11OpMextKind, parts.kind)) |inst11_op_mext_kind| {
                                                    switch (inst11_op_mext_kind) {
                                                        .mul => {
                                                            const source1_value: IRegister = @bitCast(self.registers[parts.rs1]);
                                                            const source2_value: IRegister = @bitCast(self.registers[parts.rs2]);
                                                            const new_value = @mulWithOverflow(source1_value, source2_value)[0];
                                                            self.setRegister(parts.rd, @bitCast(new_value));
                                                        },
                                                        .divu => {
                                                            const source1_value = self.registers[parts.rs1];
                                                            const source2_value = self.registers[parts.rs2];
                                                            const new_value = source1_value / source2_value;
                                                            self.setRegister(parts.rd, new_value);
                                                        },
                                                        .mulhu => {
                                                            const source1_value: URegisterDouble = self.registers[parts.rs1];
                                                            const source2_value: URegisterDouble = self.registers[parts.rs2];
                                                            const new_value = (source1_value * source2_value) >> @bitSizeOf(URegister);
                                                            self.setRegister(parts.rd, @intCast(new_value));
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
                                const inst_parts: packed struct {
                                    rd: u5,
                                    kind: u3,
                                    rest: u17,
                                } = @bitCast(instruction.rest);

                                if (std.meta.intToEnum(Instruction11OpImmKind, inst_parts.kind)) |inst11_op_imm_kind| {
                                    switch (inst11_op_imm_kind) {
                                        .addi => {
                                            const parts: packed struct {
                                                rs1: u5,
                                                imm: i12,
                                            } = @bitCast(inst_parts.rest);
                                            const source_value: IRegister = @bitCast(self.registers[parts.rs1]);
                                            const new_value = source_value + parts.imm;
                                            self.setRegister(inst_parts.rd, @bitCast(new_value));
                                        },
                                        .slli => {
                                            const new_value = blk: {
                                                switch (cpu_kind) {
                                                    .rv32 => {
                                                        const parts: packed struct {
                                                            rs1: u5,
                                                            imm: u5,
                                                            rest: u7,
                                                        } = @bitCast(inst_parts.rest);
                                                        const source_value = self.registers[parts.rs1];
                                                        break :blk source_value << parts.imm;
                                                    },
                                                    .rv64 => {
                                                        const parts: packed struct {
                                                            rs1: u5,
                                                            imm: u6,
                                                            rest: u6,
                                                        } = @bitCast(inst_parts.rest);
                                                        const source_value = self.registers[parts.rs1];
                                                        break :blk source_value << parts.imm;
                                                    },
                                                }
                                            };
                                            self.setRegister(inst_parts.rd, @bitCast(new_value));
                                        },
                                        .sltiu => {
                                            const parts: packed struct {
                                                rs1: u5,
                                                imm: i12,
                                            } = @bitCast(inst_parts.rest);
                                            const source_value: IRegister = @bitCast(self.registers[parts.rs1]);
                                            const new_value: u32 = if (source_value < parts.imm) 1 else 0;
                                            self.setRegister(inst_parts.rd, new_value);
                                        },
                                        .andi => {
                                            const parts: packed struct {
                                                rs1: u5,
                                                imm: i12,
                                            } = @bitCast(inst_parts.rest);
                                            const source_value: IRegister = @bitCast(self.registers[parts.rs1]);
                                            const new_value = source_value & parts.imm;
                                            self.setRegister(inst_parts.rd, @bitCast(new_value));
                                        },
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .op_imm = inst11_op_imm_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11OpImmKind;
                                }
                            },
                            .jal => {
                                const inst_parts: packed struct {
                                    rd: u5,
                                    imm_19_to_12: u8,
                                    imm_11: u1,
                                    imm_10_to_1: u10,
                                    imm_20: u1,
                                } = @bitCast(instruction.rest);
                                const Immediate = packed struct {
                                    rest: u1,
                                    imm_10_to_1: u10,
                                    imm_11: u1,
                                    imm_19_to_12: u8,
                                    imm_20: u1,
                                };
                                const imm_value: i21 = @bitCast(Immediate{
                                    .rest = 0,
                                    .imm_10_to_1 = inst_parts.imm_10_to_1,
                                    .imm_11 = inst_parts.imm_11,
                                    .imm_19_to_12 = inst_parts.imm_19_to_12,
                                    .imm_20 = inst_parts.imm_20,
                                });
                                const new_pc: URegister = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                self.setRegister(inst_parts.rd, self.pc + instruction_size);
                                self.pc = new_pc;
                                return .{ .cont = .{ .inst11 = .{ .jal = {} } } };
                            },
                            .jalr => {
                                const inst_parts: packed struct {
                                    rd: u5,
                                    kind: u3,
                                    rs1: u5,
                                    imm: i12,
                                } = @bitCast(instruction.rest);
                                if (self.registers[inst_parts.rs1] == U_MAX) {
                                    // TODO: this is a hack...if rs1 contains the return address, just set pc to it so we exit
                                    self.setRegister(inst_parts.rd, self.pc + instruction_size);
                                    self.pc = self.registers[inst_parts.rs1];
                                } else {
                                    const source_value: IRegister = @bitCast(self.registers[inst_parts.rs1]);
                                    const new_pc = @as(URegister, @intCast(source_value + inst_parts.imm)) & ~@as(URegister, 1);
                                    self.setRegister(inst_parts.rd, self.pc + instruction_size);
                                    self.pc = new_pc;
                                }
                                return .{ .cont = .{ .inst11 = .{ .jalr = {} } } };
                            },
                            .lui => {
                                const inst_parts: packed struct {
                                    rd: u5,
                                    imm: u20,
                                } = @bitCast(instruction.rest);
                                self.setRegister(inst_parts.rd, inst_parts.imm);
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst11 = .{ .lui = {} } } };
                            },
                            .auipc => {
                                const inst_parts: packed struct {
                                    rd: u5,
                                    imm: u20,
                                } = @bitCast(instruction.rest);
                                self.setRegister(inst_parts.rd, self.pc + inst_parts.imm);
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst11 = .{ .auipc = {} } } };
                            },
                            .branch => {
                                const inst_parts: packed struct {
                                    imm_11: u1,
                                    imm_4_to_1: u4,
                                    kind: u3,
                                    rs1: u5,
                                    rs2: u5,
                                    imm_10_to_5: u6,
                                    imm_12: u1,
                                } = @bitCast(instruction.rest);
                                const Immediate = packed struct {
                                    rest: u1,
                                    imm_4_to_1: u4,
                                    imm_10_to_5: u6,
                                    imm_11: u1,
                                    imm_12: u1,
                                };
                                const imm_value: i13 = @bitCast(Immediate{
                                    .rest = 0,
                                    .imm_4_to_1 = inst_parts.imm_4_to_1,
                                    .imm_10_to_5 = inst_parts.imm_10_to_5,
                                    .imm_11 = inst_parts.imm_11,
                                    .imm_12 = inst_parts.imm_12,
                                });
                                if (std.meta.intToEnum(Instruction11BranchKind, inst_parts.kind)) |inst11_branch_kind| {
                                    const cond = switch (inst11_branch_kind) {
                                        .beq => @as(IRegister, @bitCast(self.registers[inst_parts.rs1])) == @as(IRegister, @bitCast(self.registers[inst_parts.rs2])),
                                        .bne => @as(IRegister, @bitCast(self.registers[inst_parts.rs1])) != @as(IRegister, @bitCast(self.registers[inst_parts.rs2])),
                                        .blt => @as(IRegister, @bitCast(self.registers[inst_parts.rs1])) < @as(IRegister, @bitCast(self.registers[inst_parts.rs2])),
                                        .bge => @as(IRegister, @bitCast(self.registers[inst_parts.rs1])) >= @as(IRegister, @bitCast(self.registers[inst_parts.rs2])),
                                        .bltu => self.registers[inst_parts.rs1] < self.registers[inst_parts.rs2],
                                        .bgeu => self.registers[inst_parts.rs1] >= self.registers[inst_parts.rs2],
                                    };
                                    if (cond) {
                                        self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                    } else {
                                        self.pc += instruction_size;
                                    }
                                    return .{ .cont = .{ .inst11 = .{ .branch = inst11_branch_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11BranchKind;
                                }
                            },
                            .load => {
                                const inst_parts: packed struct {
                                    rd: u5,
                                    kind: u3,
                                    rs1: u5,
                                    imm: i12,
                                } = @bitCast(instruction.rest);
                                const source_address: URegister = @intCast(@as(IRegister, @intCast(self.registers[inst_parts.rs1])) + inst_parts.imm);

                                if (std.meta.intToEnum(Instruction11LoadKind, inst_parts.kind)) |inst11_load_kind| {
                                    switch (inst11_load_kind) {
                                        .lb => self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, mem[source_address]))),
                                        .lh => self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, std.mem.readInt(i16, mem[source_address..][0..2], .little)))),
                                        .lw => self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, std.mem.readInt(i32, mem[source_address..][0..4], .little)))),
                                        .ld => {
                                            if (cpu_kind != .rv64) {
                                                return error.RV64OnlyInstruction;
                                            }
                                            self.setRegister(inst_parts.rd, @bitCast(std.mem.readInt(URegister, mem[source_address..][0..8], .little)));
                                        },
                                        .lbu => self.setRegister(inst_parts.rd, mem[source_address]),
                                        .lhu => self.setRegister(inst_parts.rd, std.mem.readInt(u16, mem[source_address..][0..2], .little)),
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .load = inst11_load_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11LoadKind;
                                }
                            },
                            .store => {
                                const inst_parts: packed struct {
                                    imm_4_to_0: u5,
                                    kind: u3,
                                    rs1: u5,
                                    rs2: u5,
                                    imm_11_to_5: u7,
                                } = @bitCast(instruction.rest);
                                const Immediate = packed struct {
                                    imm_4_to_0: u5,
                                    imm_11_to_5: u7,
                                };
                                const imm_value: i12 = @bitCast(Immediate{
                                    .imm_4_to_0 = inst_parts.imm_4_to_0,
                                    .imm_11_to_5 = inst_parts.imm_11_to_5,
                                });
                                const dest_address: URegister = @intCast(@as(IRegister, @intCast(self.registers[inst_parts.rs1])) + imm_value);
                                const source_value = self.registers[inst_parts.rs2];

                                if (std.meta.intToEnum(Instruction11StoreKind, inst_parts.kind)) |inst11_store_kind| {
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
                                const inst_parts: packed struct {
                                    rd: u5,
                                    kind: u3,
                                    rs1: u5,
                                    imm: u12,
                                } = @bitCast(instruction.rest);

                                if (std.meta.intToEnum(Instruction11SystemKind, inst_parts.kind)) |inst11_system_kind| {
                                    switch (inst11_system_kind) {
                                        .ecall_ebreak => {
                                            switch (inst_parts.imm) {
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
                                            const csr_address = inst_parts.imm;
                                            const csr_value = try self.getCsr(csr_address);
                                            const source_value = self.registers[inst_parts.rs1];
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            try self.setCsr(csr_address, source_value);
                                        },
                                        .csrrs => {
                                            const csr_address = inst_parts.imm;
                                            const csr_value = try self.getCsr(csr_address);
                                            const source_value = self.registers[inst_parts.rs1];
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            if (source_value != 0) {
                                                try self.setCsr(csr_address, csr_value | source_value);
                                            }
                                        },
                                        .csrrc => {
                                            const csr_address = inst_parts.imm;
                                            const csr_value = try self.getCsr(csr_address);
                                            const source_value = self.registers[inst_parts.rs1];
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            if (source_value != 0) {
                                                try self.setCsr(csr_address, csr_value & (~source_value));
                                            }
                                        },
                                        .csrrwi => {
                                            const csr_address = inst_parts.imm;
                                            const csr_value = try self.getCsr(csr_address);
                                            const source_value = self.registers[inst_parts.rs1];
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            try self.setCsr(csr_address, source_value);
                                        },
                                        .csrrsi => {
                                            const csr_address = inst_parts.imm;
                                            const csr_value = try self.getCsr(csr_address);
                                            const source_value = self.registers[inst_parts.rs1];
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            if (source_value != 0) {
                                                try self.setCsr(csr_address, csr_value | source_value);
                                            }
                                        },
                                        .csrrci => {
                                            const csr_address = inst_parts.imm;
                                            const csr_value = try self.getCsr(csr_address);
                                            const source_value = self.registers[inst_parts.rs1];
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            if (source_value != 0) {
                                                try self.setCsr(csr_address, csr_value & (~source_value));
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
                                const inst_parts: packed struct {
                                    rd: u5,
                                    kind: u3,
                                    rs1: u5,
                                    imm: i12,
                                } = @bitCast(instruction.rest);

                                if (std.meta.intToEnum(Instruction11RV64IKind, inst_parts.kind)) |inst11_rv64i_kind| {
                                    switch (inst11_rv64i_kind) {
                                        .addiw => {
                                            const source_value: IRegister = @bitCast(self.registers[inst_parts.rs1]);
                                            const new_value = @addWithOverflow(source_value, inst_parts.imm)[0];
                                            self.setRegister(inst_parts.rd, @bitCast(new_value));
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

        fn setRegister(self: *Cpu(cpu_kind), register: usize, value: URegister) void {
            if (register != 0) {
                self.registers[register] = value;
            }
        }

        fn getCsr(self: Cpu(cpu_kind), address: usize) !URegister {
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

        fn setCsr(self: *Cpu(cpu_kind), address: usize, value: URegister) !void {
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
    addi4spn = 0b000,
    sw = 0b110,
};
pub const Instruction00 = union(Instruction00Kind) {
    addi4spn,
    sw,
};
pub const Instruction01Kind = enum(u3) {
    addi = 0b000,
    jal = 0b001,
    li = 0b010,
    addi16sp_lui = 0b011,
    ssas = 0b100,
    j = 0b101,
    beqz = 0b110,
    bnez = 0b111,
};
pub const Instruction01 = union(Instruction01Kind) {
    addi,
    jal,
    li,
    addi16sp_lui,
    ssas: Instruction01Ssas,
    j,
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
    ldsp = 0b011,
    jr_add = 0b100,
    sdsp = 0b111,
};
pub const Instruction10 = union(Instruction10Kind) {
    ldsp,
    jr_add: Instruction10JraddKind,
    sdsp,
};
pub const Instruction10JraddKind = enum {
    jr,
    add,
};
pub const Instruction11Kind = enum(u5) {
    op = 0b01100,
    op_imm = 0b00100,
    jal = 0b11011,
    jalr = 0b11001,
    lui = 0b01101,
    auipc = 0b00101,
    branch = 0b11000,
    load = 0b00000,
    store = 0b01000,
    fence = 0b00011,
    system = 0b11100,
    rv64i = 0b00110,
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
    ld = 0b011,
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
