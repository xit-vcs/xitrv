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

            if (self.pc >= mem.len) {
                return error.PcOutOfBounds;
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
                            .lw => {
                                const inst_parts: packed struct {
                                    rd: u3,
                                    imm_6: u1,
                                    imm_2: u1,
                                    rs1: u3,
                                    imm_5_to_3: u3,
                                } = @bitCast(instruction.rest);
                                const imm_value: u7 = @bitCast(packed struct {
                                    rest: u2,
                                    imm_2: u1,
                                    imm_5_to_3: u3,
                                    imm_6: u1,
                                }{
                                    .rest = 0,
                                    .imm_2 = inst_parts.imm_2,
                                    .imm_5_to_3 = inst_parts.imm_5_to_3,
                                    .imm_6 = inst_parts.imm_6,
                                });
                                const rs1_register = 8 + @as(URegister, inst_parts.rs1);
                                const rd_register = 8 + @as(URegister, inst_parts.rd);
                                const source_address = self.registers[rs1_register] + imm_value;
                                const value = std.mem.readInt(i32, mem[source_address..][0..4], .little);
                                self.setRegister(rd_register, @bitCast(@as(IRegister, value)));
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst00 = .{ .lw = {} } } };
                            },
                            .ld => {
                                if (cpu_kind != .rv64) {
                                    return error.RV64OnlyInstruction;
                                }
                                const inst_parts: packed struct {
                                    rd: u3,
                                    imm_7_to_6: u2,
                                    rs1: u3,
                                    imm_5_to_3: u3,
                                } = @bitCast(instruction.rest);
                                const imm_value: u8 = @bitCast(packed struct {
                                    rest: u3,
                                    imm_5_to_3: u3,
                                    imm_7_to_6: u2,
                                }{
                                    .rest = 0,
                                    .imm_5_to_3 = inst_parts.imm_5_to_3,
                                    .imm_7_to_6 = inst_parts.imm_7_to_6,
                                });
                                const rs1_register = 8 + @as(URegister, inst_parts.rs1);
                                const rd_register = 8 + @as(URegister, inst_parts.rd);
                                const source_address = self.registers[rs1_register] + imm_value;
                                self.setRegister(rd_register, std.mem.readInt(u64, mem[source_address..][0..8], .little));
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst00 = .{ .ld = {} } } };
                            },
                            .sw => {
                                const inst_parts: packed struct {
                                    rs2: u3,
                                    imm_6: u1,
                                    imm_2: u1,
                                    rs1: u3,
                                    imm_5_to_3: u3,
                                } = @bitCast(instruction.rest);
                                const imm_value: u7 = @bitCast(packed struct {
                                    rest: u2,
                                    imm_2: u1,
                                    imm_5_to_3: u3,
                                    imm_6: u1,
                                }{
                                    .rest = 0,
                                    .imm_2 = inst_parts.imm_2,
                                    .imm_5_to_3 = inst_parts.imm_5_to_3,
                                    .imm_6 = inst_parts.imm_6,
                                });
                                const rs1_register = 8 + @as(URegister, inst_parts.rs1);
                                const rs2_register = 8 + @as(URegister, inst_parts.rs2);
                                const rs2_value: u32 = @intCast(self.registers[rs2_register]);
                                const dest_address = self.registers[rs1_register] + imm_value;
                                @memcpy(mem[dest_address .. dest_address + 4], &std.mem.toBytes(rs2_value));
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst00 = .{ .sw = {} } } };
                            },
                            .sd => {
                                if (cpu_kind != .rv64) {
                                    return error.RV64OnlyInstruction;
                                }
                                const inst_parts: packed struct {
                                    rs2: u3,
                                    imm_7_to_6: u2,
                                    rs1: u3,
                                    imm_5_to_3: u3,
                                } = @bitCast(instruction.rest);
                                const imm_value: u8 = @bitCast(packed struct {
                                    rest: u3,
                                    imm_5_to_3: u3,
                                    imm_7_to_6: u2,
                                }{
                                    .rest = 0,
                                    .imm_5_to_3 = inst_parts.imm_5_to_3,
                                    .imm_7_to_6 = inst_parts.imm_7_to_6,
                                });
                                const rs1_register = 8 + @as(URegister, inst_parts.rs1);
                                const rs2_register = 8 + @as(URegister, inst_parts.rs2);
                                const rs2_value = self.registers[rs2_register];
                                const dest_address = self.registers[rs1_register] + imm_value;
                                @memcpy(mem[dest_address .. dest_address + 8], &std.mem.toBytes(rs2_value));
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst00 = .{ .sd = {} } } };
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
                                    // C.JAL offset: same encoding as C.J
                                    const inst_parts: packed struct {
                                        imm_5: u1,
                                        imm_3_to_1: u3,
                                        imm_7: u1,
                                        imm_6: u1,
                                        imm_10: u1,
                                        imm_9_to_8: u2,
                                        imm_4: u1,
                                        imm_11: u1,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        zero: u1,
                                        imm_3_to_1: u3,
                                        imm_4: u1,
                                        imm_5: u1,
                                        imm_6: u1,
                                        imm_7: u1,
                                        imm_9_to_8: u2,
                                        imm_10: u1,
                                        imm_11: u1,
                                    };
                                    const imm_value: i12 = @bitCast(Immediate{
                                        .zero = 0,
                                        .imm_3_to_1 = inst_parts.imm_3_to_1,
                                        .imm_4 = inst_parts.imm_4,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_6 = inst_parts.imm_6,
                                        .imm_7 = inst_parts.imm_7,
                                        .imm_9_to_8 = inst_parts.imm_9_to_8,
                                        .imm_10 = inst_parts.imm_10,
                                        .imm_11 = inst_parts.imm_11,
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
                                    self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, imm_value)));
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
                                                nzimm_5: u1,
                                                nzimm_8_to_7: u2,
                                                nzimm_6: u1,
                                                nzimm_4: u1,
                                            } = @bitCast(inst_parts.imm_4_to_0);
                                            const imm_value: i10 = @bitCast(packed struct {
                                                rest: u4,
                                                nzimm_4: u1,
                                                nzimm_5: u1,
                                                nzimm_6: u1,
                                                nzimm_8_to_7: u2,
                                                nzimm_9: u1,
                                            }{
                                                .rest = 0,
                                                .nzimm_4 = imm_parts.nzimm_4,
                                                .nzimm_5 = imm_parts.nzimm_5,
                                                .nzimm_6 = imm_parts.nzimm_6,
                                                .nzimm_8_to_7 = imm_parts.nzimm_8_to_7,
                                                .nzimm_9 = inst_parts.imm_5,
                                            });
                                            self.setRegister(2, @bitCast(@as(IRegister, @bitCast(self.registers[2])) + imm_value));
                                            self.pc += instruction_size;
                                            break :blk .{ .addi16sp_lui = {} };
                                        },
                                        else => {
                                            // C.LUI rd, nzimm: rd = sext(nzimm[17:12]) << 12
                                            const imm_value: i6 = @bitCast(packed struct {
                                                imm_4_to_0: u5,
                                                imm_5: u1,
                                            }{
                                                .imm_4_to_0 = inst_parts.imm_4_to_0,
                                                .imm_5 = inst_parts.imm_5,
                                            });
                                            const extended: IRegister = @as(IRegister, imm_value) << 12;
                                            self.setRegister(inst_parts.rd, @bitCast(extended));
                                            self.pc += instruction_size;
                                            break :blk .{ .addi16sp_lui = {} };
                                        },
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
                                                    self.setRegister(rd_register, @bitCast(@as(IRegister, new_value)));
                                                    break :blk2 .{ .srai = {} };
                                                },
                                                .andi => {
                                                    const rd_register = 8 + @as(URegister, inst_parts.rd);
                                                    const imm_value: i6 = @bitCast(packed struct {
                                                        imm_4_to_0: u5,
                                                        imm_5: u1,
                                                    }{
                                                        .imm_4_to_0 = inst_parts.rest_4_to_0,
                                                        .imm_5 = inst_parts.rest_5,
                                                    });
                                                    const source_value: IRegister = @bitCast(self.registers[rd_register]);
                                                    self.setRegister(rd_register, @bitCast(source_value & @as(IRegister, imm_value)));
                                                    break :blk2 .{ .andi = {} };
                                                },
                                                .sub_and => {
                                                    const rest_4_to_0_parts: packed struct {
                                                        rs2: u3,
                                                        kind: u2,
                                                    } = @bitCast(inst_parts.rest_4_to_0);
                                                    const rd_register = 8 + @as(URegister, inst_parts.rd);
                                                    const rs2_register = 8 + @as(URegister, rest_4_to_0_parts.rs2);
                                                    const rd_value = self.registers[rd_register];
                                                    const rs2_value = self.registers[rs2_register];
                                                    if (inst_parts.rest_5 == 0) {
                                                        if (std.meta.intToEnum(Instruction01SsasSubandKind, rest_4_to_0_parts.kind)) |inst01_ssas_suband_kind| {
                                                            switch (inst01_ssas_suband_kind) {
                                                                .sub => self.setRegister(rd_register, @subWithOverflow(rd_value, rs2_value)[0]),
                                                                .xor_ => self.setRegister(rd_register, rd_value ^ rs2_value),
                                                                .or_ => self.setRegister(rd_register, rd_value | rs2_value),
                                                                .and_ => self.setRegister(rd_register, rd_value & rs2_value),
                                                            }
                                                            break :blk2 .{ .sub_and = inst01_ssas_suband_kind };
                                                        } else |_| {
                                                            return error.InvalidInstruction01SsasSubandKind;
                                                        }
                                                    } else {
                                                        if (cpu_kind != .rv64) {
                                                            return error.RV64OnlyInstruction;
                                                        }
                                                        if (std.meta.intToEnum(Instruction01SsasSubwAddwKind, rest_4_to_0_parts.kind)) |inst01_ssas_subw_addw_kind| {
                                                            const rd_32: i32 = @truncate(@as(IRegister, @bitCast(rd_value)));
                                                            const rs2_32: i32 = @truncate(@as(IRegister, @bitCast(rs2_value)));
                                                            switch (inst01_ssas_subw_addw_kind) {
                                                                .subw => {
                                                                    const result: i32 = @subWithOverflow(rd_32, rs2_32)[0];
                                                                    self.setRegister(rd_register, @bitCast(@as(IRegister, result)));
                                                                },
                                                                .addw => {
                                                                    const result: i32 = @addWithOverflow(rd_32, rs2_32)[0];
                                                                    self.setRegister(rd_register, @bitCast(@as(IRegister, result)));
                                                                },
                                                            }
                                                            break :blk2 .{ .sub_and = inst01_ssas_subw_addw_kind.toSubandKind() };
                                                        } else |_| {
                                                            return error.InvalidInstruction01SsasSubwAddwKind;
                                                        }
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
                                    // C.J offset: imm[11|4|9:8|10|6|7|3:1|5] at inst[12|11|10:9|8|7|6|5:3|2]
                                    const inst_parts: packed struct {
                                        imm_5: u1,
                                        imm_3_to_1: u3,
                                        imm_7: u1,
                                        imm_6: u1,
                                        imm_10: u1,
                                        imm_9_to_8: u2,
                                        imm_4: u1,
                                        imm_11: u1,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        zero: u1,
                                        imm_3_to_1: u3,
                                        imm_4: u1,
                                        imm_5: u1,
                                        imm_6: u1,
                                        imm_7: u1,
                                        imm_9_to_8: u2,
                                        imm_10: u1,
                                        imm_11: u1,
                                    };
                                    const imm_value: i12 = @bitCast(Immediate{
                                        .zero = 0,
                                        .imm_3_to_1 = inst_parts.imm_3_to_1,
                                        .imm_4 = inst_parts.imm_4,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_6 = inst_parts.imm_6,
                                        .imm_7 = inst_parts.imm_7,
                                        .imm_9_to_8 = inst_parts.imm_9_to_8,
                                        .imm_10 = inst_parts.imm_10,
                                        .imm_11 = inst_parts.imm_11,
                                    });
                                    self.pc = @intCast(@as(IRegister, @intCast(self.pc)) + imm_value);
                                    break :blk .{ .j = {} };
                                },
                                .beqz => {
                                    // C.BEQZ offset: imm[8|4:3|7:6|2:1|5] at inst[12|11:10|6:5|4:3|2]
                                    const inst_parts: packed struct {
                                        imm_5: u1,
                                        imm_2_to_1: u2,
                                        imm_7_to_6: u2,
                                        rs1: u3,
                                        imm_4_to_3: u2,
                                        imm_8: u1,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        zero: u1,
                                        imm_2_to_1: u2,
                                        imm_4_to_3: u2,
                                        imm_5: u1,
                                        imm_7_to_6: u2,
                                        imm_8: u1,
                                    };
                                    const imm_value: i9 = @bitCast(Immediate{
                                        .zero = 0,
                                        .imm_2_to_1 = inst_parts.imm_2_to_1,
                                        .imm_4_to_3 = inst_parts.imm_4_to_3,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_7_to_6 = inst_parts.imm_7_to_6,
                                        .imm_8 = inst_parts.imm_8,
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
                                    // C.BNEZ offset: same encoding as C.BEQZ
                                    const inst_parts: packed struct {
                                        imm_5: u1,
                                        imm_2_to_1: u2,
                                        imm_7_to_6: u2,
                                        rs1: u3,
                                        imm_4_to_3: u2,
                                        imm_8: u1,
                                    } = @bitCast(instruction.rest);
                                    const Immediate = packed struct {
                                        zero: u1,
                                        imm_2_to_1: u2,
                                        imm_4_to_3: u2,
                                        imm_5: u1,
                                        imm_7_to_6: u2,
                                        imm_8: u1,
                                    };
                                    const imm_value: i9 = @bitCast(Immediate{
                                        .zero = 0,
                                        .imm_2_to_1 = inst_parts.imm_2_to_1,
                                        .imm_4_to_3 = inst_parts.imm_4_to_3,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_7_to_6 = inst_parts.imm_7_to_6,
                                        .imm_8 = inst_parts.imm_8,
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
                                .slli => {
                                    const inst_parts: packed struct {
                                        rest_4_to_0: u5,
                                        rd: u5,
                                        rest_5: u1,
                                    } = @bitCast(instruction.rest);
                                    const shamt = switch (cpu_kind) {
                                        .rv32 => @as(u5, inst_parts.rest_4_to_0),
                                        .rv64 => @as(u6, @bitCast(packed struct { lo: u5, hi: u1 }{
                                            .lo = inst_parts.rest_4_to_0,
                                            .hi = inst_parts.rest_5,
                                        })),
                                    };
                                    self.setRegister(inst_parts.rd, self.registers[inst_parts.rd] << shamt);
                                    self.pc += instruction_size;
                                    break :blk .{ .slli = {} };
                                },
                                .lwsp => {
                                    const inst_parts: packed struct {
                                        imm_7_to_6: u2,
                                        imm_4_to_2: u3,
                                        rd: u5,
                                        imm_5: u1,
                                    } = @bitCast(instruction.rest);
                                    const imm_value: u8 = @bitCast(packed struct {
                                        rest: u2,
                                        imm_4_to_2: u3,
                                        imm_5: u1,
                                        imm_7_to_6: u2,
                                    }{
                                        .rest = 0,
                                        .imm_4_to_2 = inst_parts.imm_4_to_2,
                                        .imm_5 = inst_parts.imm_5,
                                        .imm_7_to_6 = inst_parts.imm_7_to_6,
                                    });
                                    const sp = self.registers[2];
                                    const source_address = sp + imm_value;
                                    const value = std.mem.readInt(i32, mem[source_address..][0..4], .little);
                                    self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, value)));
                                    self.pc += instruction_size;
                                    break :blk .{ .lwsp = {} };
                                },
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
                                .jr_jalr_mv_add => {
                                    const inst_parts: packed struct {
                                        rs2: u5,
                                        rs1_or_rd: u5,
                                        kind: u1,
                                    } = @bitCast(instruction.rest);
                                    switch (inst_parts.kind) {
                                        0 => {
                                            if (inst_parts.rs2 == 0) {
                                                // C.JR rs1
                                                self.pc = self.registers[inst_parts.rs1_or_rd];
                                                break :blk .{ .jr_jalr_mv_add = .jr };
                                            } else {
                                                // C.MV rd, rs2
                                                self.setRegister(inst_parts.rs1_or_rd, self.registers[inst_parts.rs2]);
                                                self.pc += instruction_size;
                                                break :blk .{ .jr_jalr_mv_add = .mv };
                                            }
                                        },
                                        1 => {
                                            if (inst_parts.rs2 == 0) {
                                                // C.JALR rs1
                                                const link = self.pc + instruction_size;
                                                self.pc = self.registers[inst_parts.rs1_or_rd];
                                                self.setRegister(1, link); // ra = x1
                                                break :blk .{ .jr_jalr_mv_add = .jalr };
                                            } else {
                                                // C.ADD rd, rs2
                                                const rd_register = inst_parts.rs1_or_rd;
                                                const new_value = @addWithOverflow(self.registers[rd_register], self.registers[inst_parts.rs2])[0];
                                                self.setRegister(rd_register, new_value);
                                                self.pc += instruction_size;
                                                break :blk .{ .jr_jalr_mv_add = .add };
                                            }
                                        },
                                    }
                                },
                                .swsp => {
                                    const inst_parts: packed struct {
                                        rs2: u5,
                                        imm_7_to_6: u2,
                                        imm_5_to_2: u4,
                                    } = @bitCast(instruction.rest);
                                    const imm_value: u8 = @bitCast(packed struct {
                                        rest: u2,
                                        imm_5_to_2: u4,
                                        imm_7_to_6: u2,
                                    }{
                                        .rest = 0,
                                        .imm_5_to_2 = inst_parts.imm_5_to_2,
                                        .imm_7_to_6 = inst_parts.imm_7_to_6,
                                    });
                                    const sp = self.registers[2];
                                    const rs2_value: u32 = @intCast(self.registers[inst_parts.rs2]);
                                    const dest_address = sp + imm_value;
                                    @memcpy(mem[dest_address .. dest_address + 4], &std.mem.toBytes(rs2_value));
                                    self.pc += instruction_size;
                                    break :blk .{ .swsp = {} };
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

                                    const source1_value = self.registers[parts.rs1];
                                    const source2_value = self.registers[parts.rs2];

                                    const inst11_op: Instruction11Op = blk: {
                                        switch (inst11_op_kind) {
                                            .base => {
                                                if (std.meta.intToEnum(Instruction11OpBaseKind, parts.kind)) |inst11_op_base_kind| {
                                                    switch (inst11_op_base_kind) {
                                                        .add => self.setRegister(parts.rd, @addWithOverflow(source1_value, source2_value)[0]),
                                                        .sll => {
                                                            const shamt = switch (cpu_kind) {
                                                                .rv32 => @as(u5, @truncate(source2_value)),
                                                                .rv64 => @as(u6, @truncate(source2_value)),
                                                            };
                                                            self.setRegister(parts.rd, source1_value << shamt);
                                                        },
                                                        .slt => {
                                                            const rs1_signed: IRegister = @bitCast(source1_value);
                                                            const rs2_signed: IRegister = @bitCast(source2_value);
                                                            self.setRegister(parts.rd, if (rs1_signed < rs2_signed) 1 else 0);
                                                        },
                                                        .sltu => self.setRegister(parts.rd, if (source1_value < source2_value) 1 else 0),
                                                        .xor_ => self.setRegister(parts.rd, source1_value ^ source2_value),
                                                        .srl => {
                                                            const shamt = switch (cpu_kind) {
                                                                .rv32 => @as(u5, @truncate(source2_value)),
                                                                .rv64 => @as(u6, @truncate(source2_value)),
                                                            };
                                                            self.setRegister(parts.rd, source1_value >> shamt);
                                                        },
                                                        .or_ => self.setRegister(parts.rd, source1_value | source2_value),
                                                        .and_ => self.setRegister(parts.rd, source1_value & source2_value),
                                                    }
                                                    break :blk .{ .base = inst11_op_base_kind };
                                                } else |_| {
                                                    return error.InvalidInstruction11OpBaseKind;
                                                }
                                            },
                                            .alt => {
                                                if (std.meta.intToEnum(Instruction11OpAltKind, parts.kind)) |inst11_op_alt_kind| {
                                                    switch (inst11_op_alt_kind) {
                                                        .sub => self.setRegister(parts.rd, @subWithOverflow(source1_value, source2_value)[0]),
                                                        .sra => {
                                                            const shamt = switch (cpu_kind) {
                                                                .rv32 => @as(u5, @truncate(source2_value)),
                                                                .rv64 => @as(u6, @truncate(source2_value)),
                                                            };
                                                            const signed_value: IRegister = @bitCast(source1_value);
                                                            self.setRegister(parts.rd, @bitCast(signed_value >> shamt));
                                                        },
                                                    }
                                                    break :blk .{ .alt = inst11_op_alt_kind };
                                                } else |_| {
                                                    return error.InvalidInstruction11OpAltKind;
                                                }
                                            },
                                            .m_ext => {
                                                if (std.meta.intToEnum(Instruction11OpMextKind, parts.kind)) |inst11_op_mext_kind| {
                                                    switch (inst11_op_mext_kind) {
                                                        .mul => {
                                                            const s1: IRegister = @bitCast(source1_value);
                                                            const s2: IRegister = @bitCast(source2_value);
                                                            self.setRegister(parts.rd, @bitCast(@mulWithOverflow(s1, s2)[0]));
                                                        },
                                                        .mulh => {
                                                            const s1: IRegisterDouble = @as(IRegister, @bitCast(source1_value));
                                                            const s2: IRegisterDouble = @as(IRegister, @bitCast(source2_value));
                                                            const result = (s1 * s2) >> @bitSizeOf(URegister);
                                                            self.setRegister(parts.rd, @bitCast(@as(IRegister, @intCast(result))));
                                                        },
                                                        .mulhsu => {
                                                            const s1: IRegisterDouble = @as(IRegister, @bitCast(source1_value));
                                                            const s2: IRegisterDouble = @intCast(source2_value);
                                                            const result = (s1 * s2) >> @bitSizeOf(URegister);
                                                            self.setRegister(parts.rd, @bitCast(@as(IRegister, @intCast(result))));
                                                        },
                                                        .mulhu => {
                                                            const s1: URegisterDouble = source1_value;
                                                            const s2: URegisterDouble = source2_value;
                                                            const result = (s1 * s2) >> @bitSizeOf(URegister);
                                                            self.setRegister(parts.rd, @intCast(result));
                                                        },
                                                        .div => {
                                                            const s1: IRegister = @bitCast(source1_value);
                                                            const s2: IRegister = @bitCast(source2_value);
                                                            if (s2 == 0) {
                                                                self.setRegister(parts.rd, U_MAX);
                                                            } else {
                                                                self.setRegister(parts.rd, @bitCast(@divTrunc(s1, s2)));
                                                            }
                                                        },
                                                        .divu => {
                                                            if (source2_value == 0) {
                                                                self.setRegister(parts.rd, U_MAX);
                                                            } else {
                                                                self.setRegister(parts.rd, source1_value / source2_value);
                                                            }
                                                        },
                                                        .rem => {
                                                            const s1: IRegister = @bitCast(source1_value);
                                                            const s2: IRegister = @bitCast(source2_value);
                                                            if (s2 == 0) {
                                                                self.setRegister(parts.rd, source1_value);
                                                            } else {
                                                                self.setRegister(parts.rd, @bitCast(@rem(s1, s2)));
                                                            }
                                                        },
                                                        .remu => {
                                                            if (source2_value == 0) {
                                                                self.setRegister(parts.rd, source1_value);
                                                            } else {
                                                                self.setRegister(parts.rd, source1_value % source2_value);
                                                            }
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
                                    const parts: packed struct {
                                        rs1: u5,
                                        imm: i12,
                                    } = @bitCast(inst_parts.rest);
                                    const source_value: IRegister = @bitCast(self.registers[parts.rs1]);

                                    switch (inst11_op_imm_kind) {
                                        .addi => {
                                            self.setRegister(inst_parts.rd, @bitCast(source_value + parts.imm));
                                        },
                                        .slti => {
                                            self.setRegister(inst_parts.rd, if (source_value < parts.imm) 1 else 0);
                                        },
                                        .sltiu => {
                                            const unsigned_source = self.registers[parts.rs1];
                                            const unsigned_imm: URegister = @bitCast(@as(IRegister, parts.imm));
                                            self.setRegister(inst_parts.rd, if (unsigned_source < unsigned_imm) 1 else 0);
                                        },
                                        .xori => {
                                            self.setRegister(inst_parts.rd, @bitCast(source_value ^ parts.imm));
                                        },
                                        .ori => {
                                            self.setRegister(inst_parts.rd, @bitCast(source_value | parts.imm));
                                        },
                                        .andi => {
                                            self.setRegister(inst_parts.rd, @bitCast(source_value & parts.imm));
                                        },
                                        .slli => {
                                            const shamt = switch (cpu_kind) {
                                                .rv32 => @as(u5, @truncate(@as(u12, @bitCast(parts.imm)))),
                                                .rv64 => @as(u6, @truncate(@as(u12, @bitCast(parts.imm)))),
                                            };
                                            self.setRegister(inst_parts.rd, self.registers[parts.rs1] << shamt);
                                        },
                                        .srli_srai => {
                                            const imm_bits: u12 = @bitCast(parts.imm);
                                            const is_arithmetic = (imm_bits >> 10) & 1 == 1;
                                            const shamt = switch (cpu_kind) {
                                                .rv32 => @as(u5, @truncate(imm_bits)),
                                                .rv64 => @as(u6, @truncate(imm_bits)),
                                            };
                                            if (is_arithmetic) {
                                                self.setRegister(inst_parts.rd, @bitCast(source_value >> shamt));
                                            } else {
                                                self.setRegister(inst_parts.rd, self.registers[parts.rs1] >> shamt);
                                            }
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
                                self.setRegister(inst_parts.rd, @as(URegister, inst_parts.imm) << 12);
                                self.pc += instruction_size;
                                return .{ .cont = .{ .inst11 = .{ .lui = {} } } };
                            },
                            .auipc => {
                                const inst_parts: packed struct {
                                    rd: u5,
                                    imm: u20,
                                } = @bitCast(instruction.rest);
                                self.setRegister(inst_parts.rd, self.pc +% (@as(URegister, inst_parts.imm) << 12));
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
                                        .lb => self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, @as(i8, @bitCast(mem[source_address]))))),
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
                                        .lwu => {
                                            if (cpu_kind != .rv64) {
                                                return error.RV64OnlyInstruction;
                                            }
                                            self.setRegister(inst_parts.rd, std.mem.readInt(u32, mem[source_address..][0..4], .little));
                                        },
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
                                            const zimm: URegister = inst_parts.rs1;
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            try self.setCsr(csr_address, zimm);
                                        },
                                        .csrrsi => {
                                            const csr_address = inst_parts.imm;
                                            const csr_value = try self.getCsr(csr_address);
                                            const zimm: URegister = inst_parts.rs1;
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            if (zimm != 0) {
                                                try self.setCsr(csr_address, csr_value | zimm);
                                            }
                                        },
                                        .csrrci => {
                                            const csr_address = inst_parts.imm;
                                            const csr_value = try self.getCsr(csr_address);
                                            const zimm: URegister = inst_parts.rs1;
                                            if (inst_parts.rd != 0) {
                                                self.setRegister(inst_parts.rd, csr_value);
                                            }
                                            if (zimm != 0) {
                                                try self.setCsr(csr_address, csr_value & (~zimm));
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
                                if (cpu_kind != .rv64) {
                                    return error.RV64OnlyInstruction;
                                }
                                const inst_parts: packed struct {
                                    rd: u5,
                                    kind: u3,
                                    rs1: u5,
                                    imm: i12,
                                } = @bitCast(instruction.rest);

                                if (std.meta.intToEnum(Instruction11RV64IKind, inst_parts.kind)) |inst11_rv64i_kind| {
                                    const src32: i32 = @truncate(@as(IRegister, @bitCast(self.registers[inst_parts.rs1])));
                                    switch (inst11_rv64i_kind) {
                                        .addiw => {
                                            const result: i32 = @addWithOverflow(src32, @as(i32, inst_parts.imm))[0];
                                            self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, result)));
                                        },
                                        .slliw => {
                                            const shamt: u5 = @truncate(@as(u12, @bitCast(inst_parts.imm)));
                                            const result: i32 = @truncate(@as(i64, @as(u32, @bitCast(src32))) << shamt);
                                            self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, result)));
                                        },
                                        .srliw_sraiw => {
                                            const imm_bits: u12 = @bitCast(inst_parts.imm);
                                            const shamt: u5 = @truncate(imm_bits);
                                            const is_arithmetic = (imm_bits >> 10) & 1 == 1;
                                            if (is_arithmetic) {
                                                const result = src32 >> shamt;
                                                self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, result)));
                                            } else {
                                                const usrc32: u32 = @bitCast(src32);
                                                const result: i32 = @bitCast(usrc32 >> shamt);
                                                self.setRegister(inst_parts.rd, @bitCast(@as(IRegister, result)));
                                            }
                                        },
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .rv64i = inst11_rv64i_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11RV64IKind;
                                }
                            },
                            .rv64_op => {
                                if (cpu_kind != .rv64) {
                                    return error.RV64OnlyInstruction;
                                }
                                const inst_parts: packed struct {
                                    rest: u18,
                                    kind: u7,
                                } = @bitCast(instruction.rest);

                                if (std.meta.intToEnum(Instruction11Rv64OpKind, inst_parts.kind)) |inst11_rv64_op_kind| {
                                    const parts: packed struct {
                                        rd: u5,
                                        funct3: u3,
                                        rs1: u5,
                                        rs2: u5,
                                    } = @bitCast(inst_parts.rest);

                                    const src1_32: i32 = @truncate(@as(IRegister, @bitCast(self.registers[parts.rs1])));
                                    const src2_32: i32 = @truncate(@as(IRegister, @bitCast(self.registers[parts.rs2])));
                                    const usrc1_32: u32 = @bitCast(src1_32);
                                    const usrc2_5: u5 = @truncate(@as(u32, @bitCast(src2_32)));

                                    switch (inst11_rv64_op_kind) {
                                        .base => {
                                            if (std.meta.intToEnum(Instruction11Rv64OpBaseKind, parts.funct3)) |rv64_op_base_kind| {
                                                const result: i32 = switch (rv64_op_base_kind) {
                                                    .addw => @addWithOverflow(src1_32, src2_32)[0],
                                                    .sllw => @bitCast(@as(u32, @bitCast(src1_32)) << usrc2_5),
                                                    .srlw => @bitCast(usrc1_32 >> usrc2_5),
                                                };
                                                self.setRegister(parts.rd, @bitCast(@as(IRegister, result)));
                                            } else |_| {
                                                return error.InvalidInstruction11Rv64OpBaseKind;
                                            }
                                        },
                                        .alt => {
                                            if (std.meta.intToEnum(Instruction11Rv64OpAltKind, parts.funct3)) |rv64_op_alt_kind| {
                                                const result: i32 = switch (rv64_op_alt_kind) {
                                                    .subw => @subWithOverflow(src1_32, src2_32)[0],
                                                    .sraw => src1_32 >> usrc2_5,
                                                };
                                                self.setRegister(parts.rd, @bitCast(@as(IRegister, result)));
                                            } else |_| {
                                                return error.InvalidInstruction11Rv64OpAltKind;
                                            }
                                        },
                                    }
                                    self.pc += instruction_size;
                                    return .{ .cont = .{ .inst11 = .{ .rv64_op = inst11_rv64_op_kind } } };
                                } else |_| {
                                    return error.InvalidInstruction11Rv64OpKind;
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
    lw = 0b010,
    ld = 0b011,
    sw = 0b110,
    sd = 0b111,
};
pub const Instruction00 = union(Instruction00Kind) {
    addi4spn,
    lw,
    ld,
    sw,
    sd,
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
    xor_ = 0b01,
    or_ = 0b10,
    and_ = 0b11,
};
pub const Instruction01SsasSubwAddwKind = enum(u2) {
    subw = 0b00,
    addw = 0b01,

    pub fn toSubandKind(self: Instruction01SsasSubwAddwKind) Instruction01SsasSubandKind {
        return @enumFromInt(@intFromEnum(self));
    }
};
pub const Instruction10Kind = enum(u3) {
    slli = 0b000,
    lwsp = 0b010,
    ldsp = 0b011,
    jr_jalr_mv_add = 0b100,
    swsp = 0b110,
    sdsp = 0b111,
};
pub const Instruction10 = union(Instruction10Kind) {
    slli,
    lwsp,
    ldsp,
    jr_jalr_mv_add: Instruction10JraddKind,
    swsp,
    sdsp,
};
pub const Instruction10JraddKind = enum {
    jr,
    jalr,
    mv,
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
    rv64_op = 0b01110,
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
    rv64_op: Instruction11Rv64OpKind,
};
pub const Instruction11OpKind = enum(u7) {
    base = 0b00000_00,
    alt = 0b01000_00,
    m_ext = 0b00000_01,
};
pub const Instruction11Op = union(Instruction11OpKind) {
    base: Instruction11OpBaseKind,
    alt: Instruction11OpAltKind,
    m_ext: Instruction11OpMextKind,
};
pub const Instruction11OpBaseKind = enum(u3) {
    add = 0b000,
    sll = 0b001,
    slt = 0b010,
    sltu = 0b011,
    xor_ = 0b100,
    srl = 0b101,
    or_ = 0b110,
    and_ = 0b111,
};
pub const Instruction11OpAltKind = enum(u3) {
    sub = 0b000,
    sra = 0b101,
};
pub const Instruction11OpMextKind = enum(u3) {
    mul = 0b000,
    mulh = 0b001,
    mulhsu = 0b010,
    mulhu = 0b011,
    div = 0b100,
    divu = 0b101,
    rem = 0b110,
    remu = 0b111,
};
pub const Instruction11OpImmKind = enum(u3) {
    addi = 0b000,
    slli = 0b001,
    slti = 0b010,
    sltiu = 0b011,
    xori = 0b100,
    srli_srai = 0b101,
    ori = 0b110,
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
    lwu = 0b110,
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
    slliw = 0b001,
    srliw_sraiw = 0b101,
};
pub const Instruction11Rv64OpKind = enum(u7) {
    base = 0b00000_00,
    alt = 0b01000_00,
};
pub const Instruction11Rv64OpBaseKind = enum(u3) {
    addw = 0b000,
    sllw = 0b001,
    srlw = 0b101,
};
pub const Instruction11Rv64OpAltKind = enum(u3) {
    subw = 0b000,
    sraw = 0b101,
};
