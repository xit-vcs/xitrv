const std = @import("std");
const xitrv = @import("xitrv");
const Cpu = xitrv.cpu.Cpu;
const CpuKind = xitrv.cpu.CpuKind;
const Elf = xitrv.elf.Elf;

const stack_size: usize = 2048;

test "hello world" {
    const allocator = std.testing.allocator;

    const hello_world = @embedFile("test/bin/hello_world");

    var mem = try allocator.alloc(u8, hello_world.len + stack_size);
    defer allocator.free(mem);
    @memcpy(mem[0..hello_world.len], hello_world);

    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);

    var cpu = Cpu(.rv32).init();

    for (0..1000) |_| {
        const step = try cpu.step(mem);
        switch (step) {
            .cont => {},
            .exit => break,
            .system => {
                switch (step.system) {
                    0 => break,
                    1 => try output.append(allocator, @intCast(cpu.registers[11])),
                    else => return error.InvalidEcall,
                }
            },
        }
    } else return error.MaxStepCountExceeded;

    try std.testing.expectEqualStrings("Hello World\n", output.items);
}

test "inc" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    try testInc(io, allocator, "zig-out/lib/libtest.so");
    try testInc(io, allocator, "zig-out/lib/libtest-no-compressed.so");
}

test "recur" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    try testRecur(io, allocator, "zig-out/lib/libtest.so");
    try testRecur(io, allocator, "zig-out/lib/libtest-no-compressed.so");
}

test "exercise" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    try testExercise(io, allocator, "zig-out/lib/libtest.so");
    try testExercise(io, allocator, "zig-out/lib/libtest-no-compressed.so");
}

fn testInc(io: std.Io, allocator: std.mem.Allocator, file_name: []const u8) !void {
    const test_file = try std.Io.Dir.cwd().openFile(io, file_name, .{});
    defer test_file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = test_file.reader(io, &read_buf);
    var elf = try Elf.init(allocator, &file_reader.interface);
    defer elf.deinit(allocator);

    const func_symbol = elf.name_to_dynsym.get("inc") orelse return error.SymbolNotFound;
    const section = elf.sections.items[func_symbol.shndx];
    const func_offset = func_symbol.value - section.addr;

    var mem = try allocator.alloc(u8, section.kind.progbits.buffer.len + stack_size);
    defer allocator.free(mem);
    @memcpy(mem[0..section.kind.progbits.buffer.len], section.kind.progbits.buffer);

    var cpu = Cpu(.rv64).init();
    cpu.pc = func_offset;
    cpu.registers[2] = section.kind.progbits.buffer.len + stack_size; // stack pointer (top of stack)
    cpu.registers[10] = 42;

    for (0..1000) |_| {
        const step = try cpu.step(mem);
        switch (step) {
            .cont => {},
            .exit => break,
            .system => {
                switch (step.system) {
                    else => return error.InvalidEcall,
                }
            },
        }
    } else return error.MaxStepCountExceeded;

    try std.testing.expectEqual(43, cpu.registers[10]);
}

fn testRecur(io: std.Io, allocator: std.mem.Allocator, file_name: []const u8) !void {
    const test_file = try std.Io.Dir.cwd().openFile(io, file_name, .{});
    defer test_file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = test_file.reader(io, &read_buf);
    var elf = try Elf.init(allocator, &file_reader.interface);
    defer elf.deinit(allocator);

    const func_symbol = elf.name_to_dynsym.get("recur") orelse return error.SymbolNotFound;
    const section = elf.sections.items[func_symbol.shndx];
    const func_offset = func_symbol.value - section.addr;

    var mem = try allocator.alloc(u8, section.kind.progbits.buffer.len + stack_size);
    defer allocator.free(mem);
    @memcpy(mem[0..section.kind.progbits.buffer.len], section.kind.progbits.buffer);

    var cpu = Cpu(.rv64).init();
    cpu.pc = func_offset;
    cpu.registers[2] = section.kind.progbits.buffer.len + stack_size; // stack pointer (top of stack)
    cpu.registers[10] = 1;

    for (0..1000) |_| {
        const step = try cpu.step(mem);
        switch (step) {
            .cont => {},
            .exit => break,
            .system => {
                switch (step.system) {
                    else => return error.InvalidEcall,
                }
            },
        }
    } else return error.MaxStepCountExceeded;

    try std.testing.expectEqual(10, cpu.registers[10]);
}

fn testExercise(io: std.Io, allocator: std.mem.Allocator, file_name: []const u8) !void {
    const test_file = try std.Io.Dir.cwd().openFile(io, file_name, .{});
    defer test_file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = test_file.reader(io, &read_buf);
    var elf = try Elf.init(allocator, &file_reader.interface);
    defer elf.deinit(allocator);

    const func_symbol = elf.name_to_dynsym.get("exercise") orelse return error.SymbolNotFound;
    const section = elf.sections.items[func_symbol.shndx];
    const func_offset = func_symbol.value - section.addr;

    var mem = try allocator.alloc(u8, section.kind.progbits.buffer.len + stack_size);
    defer allocator.free(mem);
    @memcpy(mem[0..section.kind.progbits.buffer.len], section.kind.progbits.buffer);

    var cpu = Cpu(.rv64).init();
    cpu.pc = func_offset;
    cpu.registers[2] = section.kind.progbits.buffer.len + stack_size; // stack pointer (top of stack)
    cpu.registers[10] = 42; // seed

    for (0..100_000) |_| {
        const step = try cpu.step(mem);
        switch (step) {
            .cont => {},
            .exit => break,
            .system => {
                switch (step.system) {
                    else => return error.InvalidEcall,
                }
            },
        }
    } else return error.MaxStepCountExceeded;

    try std.testing.expectEqual(1471, cpu.registers[10]);
}

// ============================================================
// R-type ALU tests (OP = 0b0110011)
// ============================================================

test "rv32 ADD" {
    var mem = testMem();
    // ADD x3, x1, x2 : funct7=0, rs2=2, rs1=1, funct3=0, rd=3
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b000, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 5;
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.registers[3]);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv64 ADD" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b000, 3, OP));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x100000005;
    cpu.registers[2] = 0x200000003;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x300000008, cpu.registers[3]);
}

test "rv32 ADD overflow" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b000, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xFFFFFFFF;
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0, cpu.registers[3]);
}

test "rv32 SUB" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0100000, 2, 1, 0b000, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 10;
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[3]);
}

test "rv64 SUB" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0100000, 2, 1, 0b000, 3, OP));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 10;
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[3]);
}

test "rv32 SUB underflow" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0100000, 2, 1, 0b000, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFFFFFFFF, cpu.registers[3]);
}

test "rv32 MUL" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b000, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 6;
    cpu.registers[2] = 7;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(42, cpu.registers[3]);
}

test "rv64 MUL" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b000, 3, OP));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 6;
    cpu.registers[2] = 7;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(42, cpu.registers[3]);
}

test "rv32 MULHU" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b011, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0x80000000;
    cpu.registers[2] = 4;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(2, cpu.registers[3]);
}

test "rv32 DIVU" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b101, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 42;
    cpu.registers[2] = 6;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[3]);
}

test "rv64 DIVU" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b101, 3, OP));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 100;
    cpu.registers[2] = 10;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(10, cpu.registers[3]);
}

test "rv32 SLL" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b001, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 1;
    cpu.registers[2] = 4;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(16, cpu.registers[3]);
}

test "rv64 SLL" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b001, 3, OP));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 1;
    cpu.registers[2] = 32;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x100000000, cpu.registers[3]);
}

test "rv32 SLT true" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b010, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = @bitCast(@as(i32, -5));
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(1, cpu.registers[3]);
}

test "rv32 SLT false" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b010, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 5;
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0, cpu.registers[3]);
}

test "rv32 SLTU true" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b011, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 1;
    cpu.registers[2] = 0xFFFFFFFF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(1, cpu.registers[3]);
}

test "rv32 SLTU false" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b011, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 5;
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0, cpu.registers[3]);
}

test "rv32 XOR" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b100, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xFF00;
    cpu.registers[2] = 0x0FF0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xF0F0, cpu.registers[3]);
}

test "rv32 SRL" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b101, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0x80000000;
    cpu.registers[2] = 4;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x08000000, cpu.registers[3]);
}

test "rv32 SRA" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0100000, 2, 1, 0b101, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0x80000000; // -2147483648
    cpu.registers[2] = 4;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xF8000000, cpu.registers[3]); // sign-extended
}

test "rv32 OR" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b110, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xF0;
    cpu.registers[2] = 0x0F;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFF, cpu.registers[3]);
}

test "rv32 AND" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b111, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xFF;
    cpu.registers[2] = 0x0F;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x0F, cpu.registers[3]);
}

// M-extension

test "rv32 MULH" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b001, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = @bitCast(@as(i32, -1));
    cpu.registers[2] = @bitCast(@as(i32, 2));
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -1))), cpu.registers[3]);
}

test "rv32 MULHSU" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b010, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = @bitCast(@as(i32, -1));
    cpu.registers[2] = 2;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -1))), cpu.registers[3]);
}

test "rv32 DIV" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b100, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = @bitCast(@as(i32, -20));
    cpu.registers[2] = @bitCast(@as(i32, 6));
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -3))), cpu.registers[3]);
}

test "rv32 DIV by zero" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b100, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 42;
    cpu.registers[2] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFFFFFFFF, cpu.registers[3]);
}

test "rv32 DIVU by zero" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b101, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 42;
    cpu.registers[2] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFFFFFFFF, cpu.registers[3]);
}

test "rv32 REM" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b110, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = @bitCast(@as(i32, -20));
    cpu.registers[2] = @bitCast(@as(i32, 6));
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -2))), cpu.registers[3]);
}

test "rv32 REMU" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b111, 3, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 20;
    cpu.registers[2] = 6;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(2, cpu.registers[3]);
}

test "rv32 write to x0 is ignored" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b000, 0, OP));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 5;
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0, cpu.registers[0]);
}

// ============================================================
// I-type ALU tests (OP_IMM = 0b0010011)
// ============================================================

test "rv32 ADDI positive" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(5), 1, 0b000, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 10;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(15, cpu.registers[2]);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv32 ADDI negative" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(-3), 1, 0b000, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 10;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[2]);
}

test "rv64 ADDI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(100), 1, 0b000, 2, OP_IMM));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x100000000;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x100000064, cpu.registers[2]);
}

test "rv32 ADDI as NOP" {
    var mem = testMem();
    // NOP = ADDI x0, x0, 0
    writeInst(&mem, 0, encodeI(0, 0, 0b000, 0, OP_IMM));
    var cpu = Cpu(.rv32).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0, cpu.registers[0]);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv32 SLLI" {
    var mem = testMem();
    // SLLI x2, x1, 4 : imm=4, funct3=001
    writeInst(&mem, 0, encodeI(4, 1, 0b001, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(16, cpu.registers[2]);
}

test "rv64 SLLI" {
    var mem = testMem();
    // SLLI x2, x1, 32 (rv64 uses 6-bit shamt)
    writeInst(&mem, 0, encodeI(32, 1, 0b001, 2, OP_IMM));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x100000000, cpu.registers[2]);
}

test "rv32 SLTI true" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(10), 1, 0b010, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = @bitCast(@as(i32, -5));
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(1, cpu.registers[2]);
}

test "rv32 SLTI false" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(5), 1, 0b010, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 10;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0, cpu.registers[2]);
}

test "rv32 SLTIU true" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(10), 1, 0b011, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 5;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(1, cpu.registers[2]);
}

test "rv32 SLTIU false" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(5), 1, 0b011, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 10;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0, cpu.registers[2]);
}

test "rv32 ANDI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(0x0F), 1, 0b111, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xFF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x0F, cpu.registers[2]);
}

test "rv64 ANDI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(0x0F), 1, 0b111, 2, OP_IMM));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0xFFFFFFFFFF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x0F, cpu.registers[2]);
}

test "rv32 XORI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(0x0F), 1, 0b100, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xFF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xF0, cpu.registers[2]);
}

test "rv32 ORI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(0x0F), 1, 0b110, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xF0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFF, cpu.registers[2]);
}

test "rv32 SRLI" {
    var mem = testMem();
    // SRLI x2, x1, 4 : imm[11:0] = 0b000000_000100
    writeInst(&mem, 0, encodeI(4, 1, 0b101, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0x80;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x08, cpu.registers[2]);
}

test "rv32 SRAI" {
    var mem = testMem();
    // SRAI x2, x1, 4 : imm[11:0] = 0b010000_000100 (bit 10 set for arithmetic)
    writeInst(&mem, 0, encodeI(0b010000_000100, 1, 0b101, 2, OP_IMM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0x80000000;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xF8000000, cpu.registers[2]);
}

test "rv64 SRLI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(32, 1, 0b101, 2, OP_IMM));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x100000000;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(1, cpu.registers[2]);
}

test "rv64 SRAI" {
    var mem = testMem();
    // SRAI x2, x1, 4 : imm = 0b010000_000100
    writeInst(&mem, 0, encodeI(0b010000_000100, 1, 0b101, 2, OP_IMM));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = @bitCast(@as(i64, -256));
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), cpu.registers[2]);
}

// ============================================================
// LUI and AUIPC tests
// ============================================================

test "rv32 LUI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeU(0x12345, 1, LUI));
    var cpu = Cpu(.rv32).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x12345000, cpu.registers[1]);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv64 LUI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeU(0x12345, 1, LUI));
    var cpu = Cpu(.rv64).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x12345000, cpu.registers[1]);
}

test "rv64 LUI negative" {
    var mem = testMem();
    // imm=0xFFFFF → upper 32 bits = 0xFFFFF000, sign-extended to 64-bit
    writeInst(&mem, 0, encodeU(0xFFFFF, 1, LUI));
    var cpu = Cpu(.rv64).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFFFFFFFFFFFFF000, cpu.registers[1]);
}

test "rv64 AUIPC negative" {
    var mem = testMem();
    // imm=0xFFFFF → -0x1000 offset, PC=32 → 32 + 0xFFFFFFFFFFFFF000
    writeInst(&mem, 32, encodeU(0xFFFFF, 1, AUIPC));
    var cpu = Cpu(.rv64).init();
    cpu.pc = 32;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(32 +% @as(u64, 0xFFFFFFFFFFFFF000), cpu.registers[1]);
}

test "rv32 AUIPC" {
    var mem = testMem();
    writeInst(&mem, 16, encodeU(0x00002, 1, AUIPC));
    var cpu = Cpu(.rv32).init();
    cpu.pc = 16;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(16 + 0x2000, cpu.registers[1]);
    try std.testing.expectEqual(20, cpu.pc);
}

test "rv64 AUIPC" {
    var mem = testMem();
    writeInst(&mem, 16, encodeU(0x00002, 1, AUIPC));
    var cpu = Cpu(.rv64).init();
    cpu.pc = 16;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(16 + 0x2000, cpu.registers[1]);
}

// ============================================================
// JAL and JALR tests
// ============================================================

test "rv32 JAL forward" {
    var mem = testMem();
    // JAL x1, +8
    writeInst(&mem, 0, encodeJ(signedToU21(8), 1, JAL));
    var cpu = Cpu(.rv32).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.registers[1]); // link = pc + 4
    try std.testing.expectEqual(8, cpu.pc);
}

test "rv64 JAL forward" {
    var mem = testMem();
    writeInst(&mem, 0, encodeJ(signedToU21(16), 1, JAL));
    var cpu = Cpu(.rv64).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.registers[1]);
    try std.testing.expectEqual(16, cpu.pc);
}

test "rv32 JALR" {
    var mem = testMem();
    // JALR x3, x1, 4
    writeInst(&mem, 0, encodeI(signedToU12(4), 1, 0b000, 3, JALR));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 100;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.registers[3]); // link = pc + 4
    try std.testing.expectEqual(104, cpu.pc); // (rs1 + imm) & ~1
}

test "rv64 JALR" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(4), 1, 0b000, 3, JALR));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 100;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.registers[3]);
    try std.testing.expectEqual(104, cpu.pc);
}

test "rv32 JALR clears bit 0" {
    var mem = testMem();
    // JALR x3, x1, 1 — target should have bit 0 cleared
    writeInst(&mem, 0, encodeI(signedToU12(1), 1, 0b000, 3, JALR));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 100;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(100, cpu.pc); // (100+1)&~1 = 100
}

// ============================================================
// Branch tests (BRANCH = 0b1100011)
// ============================================================

test "rv32 BEQ taken" {
    var mem = testMem();
    // BEQ x1, x2, +8
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b000, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 42;
    cpu.registers[2] = 42;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.pc);
}

test "rv32 BEQ not taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b000, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 42;
    cpu.registers[2] = 43;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv32 BNE taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(12), 2, 1, 0b001, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 1;
    cpu.registers[2] = 2;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(12, cpu.pc);
}

test "rv32 BNE not taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(12), 2, 1, 0b001, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 5;
    cpu.registers[2] = 5;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv32 BLT taken signed" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b100, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = @bitCast(@as(i32, -1)); // -1 < 1
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.pc);
}

test "rv32 BLT not taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b100, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 5;
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv32 BGE taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b101, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 5;
    cpu.registers[2] = 5;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.pc);
}

test "rv32 BGE not taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b101, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = @bitCast(@as(i32, -5));
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv32 BLTU taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b110, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 1;
    cpu.registers[2] = 0xFFFFFFFF; // unsigned: 1 < 0xFFFFFFFF
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.pc);
}

test "rv32 BLTU not taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b110, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xFFFFFFFF;
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv32 BGEU taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b111, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0xFFFFFFFF;
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.pc);
}

test "rv32 BGEU not taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b111, BRANCH));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv64 BEQ taken" {
    var mem = testMem();
    writeInst(&mem, 0, encodeB(signedToU13(8), 2, 1, 0b000, BRANCH));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x100000042;
    cpu.registers[2] = 0x100000042;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.pc);
}

// ============================================================
// Load tests (LOAD = 0b0000011)
// ============================================================

test "rv32 LB positive" {
    var mem = testMem();
    mem[64] = 0x42;
    writeInst(&mem, 0, encodeI(signedToU12(64), 1, 0b000, 2, LOAD));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x42, cpu.registers[2]);
}

test "rv32 LB sign extend" {
    var mem = testMem();
    mem[64] = 0x80; // -128 as signed byte
    writeInst(&mem, 0, encodeI(signedToU12(64), 1, 0b000, 2, LOAD));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -128))), cpu.registers[2]);
}

test "rv32 LH sign extend" {
    var mem = testMem();
    std.mem.writeInt(i16, mem[64..][0..2], -1000, .little);
    writeInst(&mem, 0, encodeI(signedToU12(64), 1, 0b001, 2, LOAD));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -1000))), cpu.registers[2]);
}

test "rv32 LW" {
    var mem = testMem();
    std.mem.writeInt(u32, mem[64..][0..4], 0xDEADBEEF, .little);
    writeInst(&mem, 0, encodeI(signedToU12(64), 1, 0b010, 2, LOAD));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xDEADBEEF, cpu.registers[2]);
}

test "rv64 LD" {
    var mem = testMem();
    std.mem.writeInt(u64, mem[64..][0..8], 0xDEADBEEFCAFEBABE, .little);
    writeInst(&mem, 0, encodeI(signedToU12(64), 1, 0b011, 2, LOAD));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xDEADBEEFCAFEBABE, cpu.registers[2]);
}

test "rv32 LBU" {
    var mem = testMem();
    mem[64] = 0x80;
    writeInst(&mem, 0, encodeI(signedToU12(64), 1, 0b100, 2, LOAD));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x80, cpu.registers[2]); // zero-extended, not sign-extended
}

test "rv32 LHU" {
    var mem = testMem();
    std.mem.writeInt(u16, mem[64..][0..2], 0x8000, .little);
    writeInst(&mem, 0, encodeI(signedToU12(64), 1, 0b101, 2, LOAD));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x8000, cpu.registers[2]);
}

test "rv32 load with offset" {
    var mem = testMem();
    mem[74] = 0x42;
    // LB x2, 10(x1) where x1=64 → load from addr 74
    writeInst(&mem, 0, encodeI(signedToU12(10), 1, 0b000, 2, LOAD));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 64;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x42, cpu.registers[2]);
}

// ============================================================
// Store tests (STORE = 0b0100011)
// ============================================================

test "rv32 SB" {
    var mem = testMem();
    // SB x2, 64(x1) : store byte from x2 to mem[x1+64]
    writeInst(&mem, 0, encodeS(signedToU12(64), 2, 1, 0b000, STORE));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    cpu.registers[2] = 0xAB;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xAB, mem[64]);
    try std.testing.expectEqual(0, mem[65]); // no spillover
}

test "rv32 SH" {
    var mem = testMem();
    writeInst(&mem, 0, encodeS(signedToU12(64), 2, 1, 0b001, STORE));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    cpu.registers[2] = 0xBEEF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xBEEF, std.mem.readInt(u16, mem[64..][0..2], .little));
}

test "rv32 SW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeS(signedToU12(64), 2, 1, 0b010, STORE));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 0;
    cpu.registers[2] = 0xDEADBEEF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xDEADBEEF, std.mem.readInt(u32, mem[64..][0..4], .little));
}

test "rv64 SD" {
    var mem = testMem();
    writeInst(&mem, 0, encodeS(signedToU12(64), 2, 1, 0b011, STORE));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0;
    cpu.registers[2] = 0xDEADBEEFCAFEBABE;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xDEADBEEFCAFEBABE, std.mem.readInt(u64, mem[64..][0..8], .little));
}

test "rv32 store with negative offset" {
    var mem = testMem();
    // SW x2, -4(x1) where x1=68 → store to addr 64
    writeInst(&mem, 0, encodeS(signedToU12(-4), 2, 1, 0b010, STORE));
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 68;
    cpu.registers[2] = 0x12345678;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x12345678, std.mem.readInt(u32, mem[64..][0..4], .little));
}

// ============================================================
// System / CSR tests (SYSTEM = 0b1110011)
// ============================================================

test "rv32 ECALL" {
    var mem = testMem();
    // ECALL: imm=0, rs1=0, funct3=0, rd=0
    writeInst(&mem, 0, encodeI(0, 0, 0b000, 0, SYSTEM));
    var cpu = Cpu(.rv32).init();
    cpu.registers[10] = 42;
    const step = try cpu.step(&mem);
    try std.testing.expectEqual(42, step.system);
    try std.testing.expectEqual(4, cpu.pc);
}

test "rv32 CSRRW" {
    var mem = testMem();
    // CSRRW x2, csr_addr=0x001, x1 : funct3=001, imm=csr_addr
    writeInst(&mem, 0, encodeI(0x001, 1, 0b001, 2, SYSTEM));
    var cpu = Cpu(.rv32).init();
    cpu.csrs.test_register = 99;
    cpu.registers[1] = 42;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(99, cpu.registers[2]); // old CSR value
    try std.testing.expectEqual(42, cpu.csrs.test_register); // new CSR value
}

test "rv32 CSRRS" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(0x001, 1, 0b010, 2, SYSTEM));
    var cpu = Cpu(.rv32).init();
    cpu.csrs.test_register = 0b1010;
    cpu.registers[1] = 0b0110;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0b1010, cpu.registers[2]); // old value
    try std.testing.expectEqual(0b1110, cpu.csrs.test_register); // bits set
}

test "rv32 CSRRC" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(0x001, 1, 0b011, 2, SYSTEM));
    var cpu = Cpu(.rv32).init();
    cpu.csrs.test_register = 0b1111;
    cpu.registers[1] = 0b0101;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0b1111, cpu.registers[2]); // old value
    try std.testing.expectEqual(0b1010, cpu.csrs.test_register); // bits cleared
}

test "rv32 CSRRWI" {
    var mem = testMem();
    // CSRRWI x2, csr=0x001, zimm=5 : funct3=101, rs1 field = zimm = 5
    writeInst(&mem, 0, encodeI(0x001, 5, 0b101, 2, SYSTEM));
    var cpu = Cpu(.rv32).init();
    cpu.csrs.test_register = 99;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(99, cpu.registers[2]); // old CSR value
    try std.testing.expectEqual(5, cpu.csrs.test_register); // zimm written
}

test "rv32 CSRRSI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(0x001, 3, 0b110, 2, SYSTEM));
    var cpu = Cpu(.rv32).init();
    cpu.csrs.test_register = 0b1000;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0b1000, cpu.registers[2]); // old value
    try std.testing.expectEqual(0b1011, cpu.csrs.test_register); // bits set by zimm=3
}

test "rv32 CSRRCI" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(0x001, 3, 0b111, 2, SYSTEM));
    var cpu = Cpu(.rv32).init();
    cpu.csrs.test_register = 0b1111;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0b1111, cpu.registers[2]); // old value
    try std.testing.expectEqual(0b1100, cpu.csrs.test_register); // bits cleared by zimm=3
}

// ============================================================
// RV64I extension tests (OP_IMM_32 = 0b0011011)
// ============================================================

test "rv64 ADDIW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(5), 1, 0b000, 2, OP_IMM_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 10;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(15, cpu.registers[2]);
}

test "rv64 ADDIW negative" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(signedToU12(-3), 1, 0b000, 2, OP_IMM_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 10;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[2]);
}

test "rv64 ADDIW sign extends 32-bit result" {
    var mem = testMem();
    // 0x7FFFFFFF + 1 = 0x80000000 as u32, which sign-extends to 0xFFFFFFFF80000000
    writeInst(&mem, 0, encodeI(signedToU12(1), 1, 0b000, 2, OP_IMM_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x7FFFFFFF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -2147483648))), cpu.registers[2]);
}

test "rv64 SLLIW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(4, 1, 0b001, 2, OP_IMM_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x08000000;
    _ = try cpu.step(&mem);
    // 0x08000000 << 4 = 0x80000000 as u32, sign-extends to 0xFFFFFFFF80000000
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -2147483648))), cpu.registers[2]);
}

test "rv64 SRLIW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(4, 1, 0b101, 2, OP_IMM_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x80;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x08, cpu.registers[2]);
}

test "rv64 SRAIW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeI(0b010000_000100, 1, 0b101, 2, OP_IMM_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x80000000; // -2147483648 as i32
    _ = try cpu.step(&mem);
    // -2147483648 >> 4 = -134217728, sign-extended to 64 bits
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -134217728))), cpu.registers[2]);
}

test "rv64 ADDW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b000, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x7FFFFFFF;
    cpu.registers[2] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -2147483648))), cpu.registers[3]);
}

test "rv64 SUBW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0100000, 2, 1, 0b000, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 10;
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[3]);
}

test "rv64 SLLW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b001, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x08000000;
    cpu.registers[2] = 4;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -2147483648))), cpu.registers[3]);
}

test "rv64 SRLW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000000, 2, 1, 0b101, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x80000000;
    cpu.registers[2] = 4;
    _ = try cpu.step(&mem);
    // 0x80000000 >> 4 = 0x08000000, sign-extends as positive
    try std.testing.expectEqual(0x08000000, cpu.registers[3]);
}

test "rv64 SRAW" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0100000, 2, 1, 0b101, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x80000000; // -2147483648 as i32
    cpu.registers[2] = 4;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -134217728))), cpu.registers[3]);
}

test "rv64 LWU" {
    var mem = testMem();
    std.mem.writeInt(u32, mem[64..][0..4], 0x80000000, .little);
    writeInst(&mem, 0, encodeI(signedToU12(64), 1, 0b110, 2, LOAD));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x80000000, cpu.registers[2]); // zero-extended, not sign-extended
}

// ============================================================
// Compressed instruction tests (16-bit)
// ============================================================

test "rv32 C.ADDI4SPN" {
    var mem = testMem();
    // C.ADDI4SPN rd', imm: rd' = x8+rd, result = sp + nzuimm
    // imm = 32: imm_9_to_6=0, imm_5_to_4=0b10, imm_3=0, imm_2=0
    const inst: u16 = @bitCast(packed struct { op: u2, rd: u3, imm_3: u1, imm_2: u1, imm_9_to_6: u4, imm_5_to_4: u2, kind: u3 }{
        .op = 0b00,
        .rd = 0, // x8
        .imm_3 = 0,
        .imm_2 = 0,
        .imm_9_to_6 = 0,
        .imm_5_to_4 = 0b10, // imm = 32
        .kind = 0b000,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[2] = 100; // sp
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(132, cpu.registers[8]); // sp + 32
    try std.testing.expectEqual(2, cpu.pc);
}

test "rv32 C.SW" {
    var mem = testMem();
    // C.SW rs2', offset(rs1'): store word from rs2' to mem[rs1'+offset]
    // offset = 4: imm_5_to_3=0b001, imm_2=0, imm_6=0
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u3, imm_6: u1, imm_2: u1, rs1: u3, imm_5_to_3: u3, kind: u3 }{
        .op = 0b00,
        .rs2 = 1, // x9
        .imm_6 = 0,
        .imm_2 = 0,
        .rs1 = 0, // x8
        .imm_5_to_3 = 0b001, // offset = 8
        .kind = 0b110,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 64;
    cpu.registers[9] = 0x12345678;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x12345678, std.mem.readInt(u32, mem[72..][0..4], .little));
}

test "rv32 C.ADDI" {
    var mem = testMem();
    // C.ADDI rd, nzimm: rd = rd + sext(nzimm)
    const inst: u16 = @bitCast(packed struct { op: u2, imm_4_to_0: u5, rd: u5, imm_5: u1, kind: u3 }{
        .op = 0b01,
        .imm_4_to_0 = 0b11101, // -3 as 5 low bits of i6
        .rd = 1,
        .imm_5 = 1, // sign bit (negative)
        .kind = 0b000,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 10;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[1]);
}

test "rv32 C.LI" {
    var mem = testMem();
    // C.LI rd, imm: rd = sext(imm)
    const inst: u16 = @bitCast(packed struct { op: u2, imm_4_to_0: u5, rd: u5, imm_5: u1, kind: u3 }{
        .op = 0b01,
        .imm_4_to_0 = 15,
        .rd = 3,
        .imm_5 = 0,
        .kind = 0b010,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(15, cpu.registers[3]);
}

test "rv32 C.LI negative" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, imm_4_to_0: u5, rd: u5, imm_5: u1, kind: u3 }{
        .op = 0b01,
        .imm_4_to_0 = 0b11111, // -1 as i6 low bits
        .rd = 3,
        .imm_5 = 1,
        .kind = 0b010,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, -1))), cpu.registers[3]);
}

test "rv32 C.ADDI16SP" {
    var mem = testMem();
    // C.ADDI16SP: rd=2 (sp), imm = {imm_9, imm_8_to_6, imm_5, imm_4, 0000}
    // For imm=16: imm_9=0, imm_8_to_6=0b000, imm_5=1, imm_4=0
    // imm_4_to_0 encodes as packed {imm_8_to_6: u3, imm_5: u1, imm_4: u1}
    const inst: u16 = @bitCast(packed struct { op: u2, imm_4_to_0: u5, rd: u5, imm_5: u1, kind: u3 }{
        .op = 0b01,
        .imm_4_to_0 = 0b10000, // {imm_4=1, imm_5=0, imm_8_to_6=000}
        .rd = 2,
        .imm_5 = 0, // imm_9 = 0
        .kind = 0b011,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[2] = 100;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(116, cpu.registers[2]);
}

test "rv64 C.SRLI" {
    var mem = testMem();
    // C.SRLI rd', shamt: rd' = rd' >> shamt
    const inst: u16 = @bitCast(packed struct { op: u2, rest_4_to_0: u5, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rest_4_to_0 = 4, // shamt = 4
        .rd = 0, // x8
        .kind = 0b00, // srli
        .rest_5 = 0,
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[8] = 0x100;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x10, cpu.registers[8]);
}

test "rv64 C.SRAI" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, rest_4_to_0: u5, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rest_4_to_0 = 4, // shamt = 4
        .rd = 0, // x8
        .kind = 0b01, // srai
        .rest_5 = 0,
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[8] = @bitCast(@as(i64, -256));
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), cpu.registers[8]);
}

test "rv32 C.SUB" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u3, sub_kind: u2, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rs2 = 1, // x9
        .sub_kind = 0b00, // sub
        .rd = 0, // x8
        .kind = 0b11, // sub_and
        .rest_5 = 0,
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 10;
    cpu.registers[9] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[8]);
}

test "rv32 C.AND" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u3, sub_kind: u2, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rs2 = 1, // x9
        .sub_kind = 0b11, // and
        .rd = 0, // x8
        .kind = 0b11, // sub_and
        .rest_5 = 0,
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 0xFF;
    cpu.registers[9] = 0x0F;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x0F, cpu.registers[8]);
}

test "rv32 C.J" {
    var mem = testMem();
    // C.J offset: imm[11|4|9:8|10|6|7|3:1|5] at inst[12|11|10:9|8|7|6|5:3|2]
    // offset = +6: imm[2:1]=11, rest=0
    const inst: u16 = @bitCast(packed struct { op: u2, imm_5: u1, imm_3_to_1: u3, imm_7: u1, imm_6: u1, imm_10: u1, imm_9_to_8: u2, imm_4: u1, imm_11: u1, kind: u3 }{
        .op = 0b01,
        .imm_5 = 0,
        .imm_3_to_1 = 0b011, // offset[3:1] = 011
        .imm_7 = 0,
        .imm_6 = 0,
        .imm_10 = 0,
        .imm_9_to_8 = 0,
        .imm_4 = 0,
        .imm_11 = 0,
        .kind = 0b101,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(6, cpu.pc);
}

test "rv32 C.BEQZ taken" {
    var mem = testMem();
    // C.BEQZ offset: imm[8|4:3|7:6|2:1|5] at inst[12|11:10|6:5|4:3|2]
    // offset = 6: imm[2:1]=11, rest=0
    const inst: u16 = @bitCast(packed struct { op: u2, imm_5: u1, imm_2_to_1: u2, imm_7_to_6: u2, rs1: u3, imm_4_to_3: u2, imm_8: u1, kind: u3 }{
        .op = 0b01,
        .imm_5 = 0,
        .imm_2_to_1 = 0b11, // offset[2:1] = 11
        .imm_7_to_6 = 0,
        .rs1 = 0, // x8
        .imm_4_to_3 = 0,
        .imm_8 = 0,
        .kind = 0b110,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(6, cpu.pc);
}

test "rv32 C.BEQZ not taken" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, imm_5: u1, imm_2_to_1: u2, imm_7_to_6: u2, rs1: u3, imm_4_to_3: u2, imm_8: u1, kind: u3 }{
        .op = 0b01,
        .imm_5 = 0,
        .imm_2_to_1 = 0b11,
        .imm_7_to_6 = 0,
        .rs1 = 0,
        .imm_4_to_3 = 0,
        .imm_8 = 0,
        .kind = 0b110,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 42;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(2, cpu.pc);
}

test "rv32 C.BNEZ taken" {
    var mem = testMem();
    // C.BNEZ offset: same encoding as C.BEQZ
    // offset = 8: imm[3]=1, rest=0
    const inst: u16 = @bitCast(packed struct { op: u2, imm_5: u1, imm_2_to_1: u2, imm_7_to_6: u2, rs1: u3, imm_4_to_3: u2, imm_8: u1, kind: u3 }{
        .op = 0b01,
        .imm_5 = 0,
        .imm_2_to_1 = 0,
        .imm_7_to_6 = 0,
        .rs1 = 0, // x8
        .imm_4_to_3 = 0b01, // offset[4:3] = 01 → offset[3]=1
        .imm_8 = 0,
        .kind = 0b111,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 1;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.pc);
}

test "rv32 C.BNEZ not taken" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, imm_5: u1, imm_2_to_1: u2, imm_7_to_6: u2, rs1: u3, imm_4_to_3: u2, imm_8: u1, kind: u3 }{
        .op = 0b01,
        .imm_5 = 0,
        .imm_2_to_1 = 0,
        .imm_7_to_6 = 0,
        .rs1 = 0,
        .imm_4_to_3 = 0b01,
        .imm_8 = 0,
        .kind = 0b111,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(2, cpu.pc);
}

test "rv64 C.LDSP" {
    var mem = testMem();
    std.mem.writeInt(u64, mem[64..][0..8], 0xDEADBEEFCAFEBABE, .little);
    // C.LDSP rd, offset(sp): offset = 64
    // offset=64: imm_4_to_3=0b00, imm_5=0, imm_8_to_6=0b001 → 8*8=64? No.
    // Actually: offset = {imm_8_to_6, imm_5, imm_4_to_3, 000}
    // 64 = 0b001_000_000 → imm_8_to_6=0b001, imm_5=0, imm_4_to_3=0b00
    const inst: u16 = @bitCast(packed struct { op: u2, imm_8_to_6: u3, imm_4_to_3: u2, rd: u5, imm_5: u1, kind: u3 }{
        .op = 0b10,
        .imm_8_to_6 = 0b001,
        .imm_4_to_3 = 0b00,
        .rd = 3,
        .imm_5 = 0,
        .kind = 0b011,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[2] = 0; // sp
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xDEADBEEFCAFEBABE, cpu.registers[3]);
}

test "rv32 C.JR" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u5, rs1_or_rd: u5, jr_kind: u1, kind: u3 }{
        .op = 0b10,
        .rs2 = 0,
        .rs1_or_rd = 1, // rs1 = x1
        .jr_kind = 0, // jr
        .kind = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 42;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(42, cpu.pc);
}

test "rv32 C.ADD" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u5, rs1_or_rd: u5, add_kind: u1, kind: u3 }{
        .op = 0b10,
        .rs2 = 2,
        .rs1_or_rd = 1,
        .add_kind = 1, // add
        .kind = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[1] = 10;
    cpu.registers[2] = 5;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(15, cpu.registers[1]);
}

test "rv64 C.SDSP" {
    var mem = testMem();
    // C.SDSP rs2, offset(sp): offset = 64
    // offset = {imm_8_to_6, imm_5_to_3, 000}
    // 64 = 0b001_000_000 → imm_8_to_6=0b001, imm_5_to_3=0b000
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u5, imm_8_to_6: u3, imm_5_to_3: u3, kind: u3 }{
        .op = 0b10,
        .rs2 = 3,
        .imm_8_to_6 = 0b001,
        .imm_5_to_3 = 0b000,
        .kind = 0b111,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[2] = 0; // sp
    cpu.registers[3] = 0xDEADBEEFCAFEBABE;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xDEADBEEFCAFEBABE, std.mem.readInt(u64, mem[64..][0..8], .little));
}

// ============================================================
// RV64M OP-32 tests (MULW, DIVW, DIVUW, REMW, REMUW)
// ============================================================

test "rv64 MULW" {
    var mem = testMem();
    // MULW x3, x1, x2: funct7=0000001, funct3=000, opcode=OP_32
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b000, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 7;
    cpu.registers[2] = 6;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(42, cpu.registers[3]);
}

test "rv64 MULW overflow" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b000, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x80000000; // -2147483648 as i32
    cpu.registers[2] = 2;
    _ = try cpu.step(&mem);
    // (-2147483648 * 2) truncated to 32 bits = 0, sign-extended to 64 bits
    try std.testing.expectEqual(0, cpu.registers[3]);
}

test "rv64 DIVW" {
    var mem = testMem();
    // DIVW x3, x1, x2: funct7=0000001, funct3=100, opcode=OP_32
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b100, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 42;
    cpu.registers[2] = 5;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(8, cpu.registers[3]);
}

test "rv64 DIVW by zero" {
    var mem = testMem();
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b100, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 42;
    cpu.registers[2] = 0;
    _ = try cpu.step(&mem);
    // DIVW by zero → -1 sign-extended
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -1))), cpu.registers[3]);
}

test "rv64 DIVUW" {
    var mem = testMem();
    // DIVUW x3, x1, x2: funct7=0000001, funct3=101, opcode=OP_32
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b101, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x80000000; // 2147483648 as u32
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    // 2147483648 / 3 = 715827882, sign-extended (positive, so same)
    try std.testing.expectEqual(715827882, cpu.registers[3]);
}

test "rv64 REMW" {
    var mem = testMem();
    // REMW x3, x1, x2: funct7=0000001, funct3=110, opcode=OP_32
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b110, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 42;
    cpu.registers[2] = 5;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(2, cpu.registers[3]);
}

test "rv64 REMUW" {
    var mem = testMem();
    // REMUW x3, x1, x2: funct7=0000001, funct3=111, opcode=OP_32
    writeInst(&mem, 0, encodeR(0b0000001, 2, 1, 0b111, 3, OP_32));
    var cpu = Cpu(.rv64).init();
    cpu.registers[1] = 0x80000005; // large unsigned u32
    cpu.registers[2] = 3;
    _ = try cpu.step(&mem);
    // 0x80000005 % 3 = 2147483653 % 3 = 1
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, 1))), cpu.registers[3]);
}

// ============================================================
// Additional compressed instruction tests
// ============================================================

test "rv64 C.LD" {
    var mem = testMem();
    std.mem.writeInt(u64, mem[72..][0..8], 0xCAFEBABEDEADBEEF, .little);
    // C.LD rd', offset(rs1'): offset = {imm_5_to_3, imm_7_to_6, 000}
    // offset = 8: imm_5_to_3=0b001, imm_7_to_6=0b00
    const inst: u16 = @bitCast(packed struct { op: u2, rd: u3, imm_7_to_6: u2, rs1: u3, imm_5_to_3: u3, kind: u3 }{
        .op = 0b00,
        .rd = 1, // x9
        .imm_7_to_6 = 0b00,
        .rs1 = 0, // x8
        .imm_5_to_3 = 0b001, // offset = 8
        .kind = 0b011,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[8] = 64;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xCAFEBABEDEADBEEF, cpu.registers[9]);
}

test "rv64 C.SD" {
    var mem = testMem();
    // C.SD rs2', offset(rs1'): offset = {imm_5_to_3, imm_7_to_6, 000}
    // offset = 16: imm_5_to_3=0b010, imm_7_to_6=0b00
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u3, imm_7_to_6: u2, rs1: u3, imm_5_to_3: u3, kind: u3 }{
        .op = 0b00,
        .rs2 = 1, // x9
        .imm_7_to_6 = 0b00,
        .rs1 = 0, // x8
        .imm_5_to_3 = 0b010, // offset = 16
        .kind = 0b111,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[8] = 64;
    cpu.registers[9] = 0x123456789ABCDEF0;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x123456789ABCDEF0, std.mem.readInt(u64, mem[80..][0..8], .little));
}

test "rv32 C.LW" {
    var mem = testMem();
    std.mem.writeInt(u32, mem[72..][0..4], 0x12345678, .little);
    // C.LW rd', offset(rs1'): offset = {imm_6, imm_5_to_3, imm_2, 00}
    // offset = 8: bit 3 set → imm_5_to_3=0b001, imm_2=0, imm_6=0
    const inst: u16 = @bitCast(packed struct { op: u2, rd: u3, imm_6: u1, imm_2: u1, rs1: u3, imm_5_to_3: u3, kind: u3 }{
        .op = 0b00,
        .rd = 1, // x9
        .imm_6 = 0,
        .imm_2 = 0,
        .rs1 = 0, // x8
        .imm_5_to_3 = 0b001, // offset = 8
        .kind = 0b010,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 64;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x12345678, cpu.registers[9]);
}

test "rv32 C.JAL" {
    var mem = testMem();
    // C.JAL offset: same encoding as C.J but kind=001, links to ra
    // offset = +10: imm[3:1]=101, rest=0
    const inst: u16 = @bitCast(packed struct { op: u2, imm_5: u1, imm_3_to_1: u3, imm_7: u1, imm_6: u1, imm_10: u1, imm_9_to_8: u2, imm_4: u1, imm_11: u1, kind: u3 }{
        .op = 0b01,
        .imm_5 = 0,
        .imm_3_to_1 = 0b101, // offset[3:1] = 101 → offset = 10
        .imm_7 = 0,
        .imm_6 = 0,
        .imm_10 = 0,
        .imm_9_to_8 = 0,
        .imm_4 = 0,
        .imm_11 = 0,
        .kind = 0b001,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(10, cpu.pc);
    try std.testing.expectEqual(2, cpu.registers[1]); // ra = pc + 2
}

test "rv32 C.LUI" {
    var mem = testMem();
    // C.LUI rd, nzimm: rd = sext(nzimm) << 12
    // nzimm = 3: imm_4_to_0=0b00011, imm_5=0
    const inst: u16 = @bitCast(packed struct { op: u2, imm_4_to_0: u5, rd: u5, imm_5: u1, kind: u3 }{
        .op = 0b01,
        .imm_4_to_0 = 0b00011,
        .rd = 3,
        .imm_5 = 0,
        .kind = 0b011,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x3000, cpu.registers[3]);
}

test "rv64 C.LUI negative" {
    var mem = testMem();
    // C.LUI rd, nzimm: nzimm = -1 (all bits set) → rd = 0xFFFFF000 sign-extended
    const inst: u16 = @bitCast(packed struct { op: u2, imm_4_to_0: u5, rd: u5, imm_5: u1, kind: u3 }{
        .op = 0b01,
        .imm_4_to_0 = 0b11111,
        .rd = 3,
        .imm_5 = 1, // sign bit
        .kind = 0b011,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFFFFFFFFFFFFF000, cpu.registers[3]);
}

test "rv32 C.ANDI" {
    var mem = testMem();
    // C.ANDI rd', imm: rd' = rd' & sext(imm)
    // imm = 0x0F (i6 = 15): imm_4_to_0=0b01111, imm_5=0
    const inst: u16 = @bitCast(packed struct { op: u2, rest_4_to_0: u5, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rest_4_to_0 = 0b01111, // imm = 15
        .rd = 0, // x8
        .kind = 0b10, // andi
        .rest_5 = 0,
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 0xFF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x0F, cpu.registers[8]);
}

test "rv32 C.XOR" {
    var mem = testMem();
    // C.XOR rd', rs2': rd' = rd' ^ rs2'
    // sub_and kind=11, sub_kind=01 (xor), rest_5=0
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u3, sub_kind: u2, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rs2 = 1, // x9
        .sub_kind = 0b01, // xor
        .rd = 0, // x8
        .kind = 0b11, // sub_and
        .rest_5 = 0,
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 0xFF;
    cpu.registers[9] = 0x0F;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xF0, cpu.registers[8]);
}

test "rv32 C.OR" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u3, sub_kind: u2, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rs2 = 1, // x9
        .sub_kind = 0b10, // or
        .rd = 0, // x8
        .kind = 0b11,
        .rest_5 = 0,
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[8] = 0xF0;
    cpu.registers[9] = 0x0F;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFF, cpu.registers[8]);
}

test "rv64 C.SUBW" {
    var mem = testMem();
    // C.SUBW rd', rs2': rd' = sext((rd'[31:0] - rs2'[31:0])[31:0])
    // sub_and kind=11, sub_kind=00 (subw), rest_5=1
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u3, sub_kind: u2, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rs2 = 1, // x9
        .sub_kind = 0b00, // subw
        .rd = 0, // x8
        .kind = 0b11,
        .rest_5 = 1, // selects W variants
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[8] = 10;
    cpu.registers[9] = 3;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(7, cpu.registers[8]);
}

test "rv64 C.ADDW" {
    var mem = testMem();
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u3, sub_kind: u2, rd: u3, kind: u2, rest_5: u1, funct3: u3 }{
        .op = 0b01,
        .rs2 = 1, // x9
        .sub_kind = 0b01, // addw
        .rd = 0, // x8
        .kind = 0b11,
        .rest_5 = 1,
        .funct3 = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[8] = 0x7FFFFFFF; // max i32
    cpu.registers[9] = 1;
    _ = try cpu.step(&mem);
    // 0x7FFFFFFF + 1 = 0x80000000, sign-extended to 0xFFFFFFFF80000000
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -2147483648))), cpu.registers[8]);
}

test "rv64 C.SLLI" {
    var mem = testMem();
    // C.SLLI rd, shamt: rd = rd << shamt
    const inst: u16 = @bitCast(packed struct { op: u2, rest_4_to_0: u5, rd: u5, rest_5: u1, kind: u3 }{
        .op = 0b10,
        .rest_4_to_0 = 4, // shamt = 4
        .rd = 3,
        .rest_5 = 0,
        .kind = 0b000,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv64).init();
    cpu.registers[3] = 0xFF;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0xFF0, cpu.registers[3]);
}

test "rv32 C.LWSP" {
    var mem = testMem();
    std.mem.writeInt(u32, mem[64..][0..4], 0xDEADBEEF, .little);
    // C.LWSP rd, offset(sp): offset = {imm_7_to_6, imm_5, imm_4_to_2, 00}
    // offset = 64: 64 = 0b01_0_000_00 → imm_7_to_6=0b01, imm_5=0, imm_4_to_2=0b000
    const inst: u16 = @bitCast(packed struct { op: u2, imm_7_to_6: u2, imm_4_to_2: u3, rd: u5, imm_5: u1, kind: u3 }{
        .op = 0b10,
        .imm_7_to_6 = 0b01,
        .imm_4_to_2 = 0b000,
        .rd = 3,
        .imm_5 = 0,
        .kind = 0b010,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[2] = 0; // sp
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(i32, @bitCast(@as(u32, 0xDEADBEEF))))), cpu.registers[3]);
}

test "rv32 C.SWSP" {
    var mem = testMem();
    // C.SWSP rs2, offset(sp): offset = {imm_7_to_6, imm_5_to_2, 00}
    // offset = 64: 64 = 0b01_0000_00 → imm_7_to_6=0b01, imm_5_to_2=0b0000
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u5, imm_7_to_6: u2, imm_5_to_2: u4, kind: u3 }{
        .op = 0b10,
        .rs2 = 3,
        .imm_7_to_6 = 0b01,
        .imm_5_to_2 = 0b0000,
        .kind = 0b110,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[2] = 0; // sp
    cpu.registers[3] = 0x12345678;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(0x12345678, std.mem.readInt(u32, mem[64..][0..4], .little));
}

test "rv32 C.MV" {
    var mem = testMem();
    // C.MV rd, rs2: rd = rs2
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u5, rs1_or_rd: u5, add_kind: u1, kind: u3 }{
        .op = 0b10,
        .rs2 = 2,
        .rs1_or_rd = 3,
        .add_kind = 0, // mv (jr_kind=0 with rs2!=0)
        .kind = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[2] = 42;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(42, cpu.registers[3]);
}

test "rv32 C.JALR" {
    var mem = testMem();
    // C.JALR rs1: pc = rs1, ra = pc + 2
    const inst: u16 = @bitCast(packed struct { op: u2, rs2: u5, rs1_or_rd: u5, add_kind: u1, kind: u3 }{
        .op = 0b10,
        .rs2 = 0, // rs2=0 selects JALR (not ADD)
        .rs1_or_rd = 3,
        .add_kind = 1, // jalr (kind=1 with rs2=0)
        .kind = 0b100,
    });
    writeInst16(&mem, 0, inst);
    var cpu = Cpu(.rv32).init();
    cpu.registers[3] = 42;
    _ = try cpu.step(&mem);
    try std.testing.expectEqual(42, cpu.pc);
    try std.testing.expectEqual(2, cpu.registers[1]); // ra = pc + 2
}

// ============================================================
// Instruction encoding helpers
// ============================================================

const OP = 0b0110011;
const OP_IMM = 0b0010011;
const LUI = 0b0110111;
const AUIPC = 0b0010111;
const JAL = 0b1101111;
const JALR = 0b1100111;
const BRANCH = 0b1100011;
const LOAD = 0b0000011;
const STORE = 0b0100011;
const SYSTEM = 0b1110011;
const OP_IMM_32 = 0b0011011;
const OP_32 = 0b0111011;

fn encodeR(funct7: u7, rs2: u5, rs1: u5, funct3: u3, rd: u5, opcode: u7) u32 {
    return @bitCast(packed struct { opcode: u7, rd: u5, funct3: u3, rs1: u5, rs2: u5, funct7: u7 }{
        .opcode = opcode,
        .rd = rd,
        .funct3 = funct3,
        .rs1 = rs1,
        .rs2 = rs2,
        .funct7 = funct7,
    });
}

fn encodeI(imm: u12, rs1: u5, funct3: u3, rd: u5, opcode: u7) u32 {
    return @bitCast(packed struct { opcode: u7, rd: u5, funct3: u3, rs1: u5, imm: u12 }{
        .opcode = opcode,
        .rd = rd,
        .funct3 = funct3,
        .rs1 = rs1,
        .imm = imm,
    });
}

fn encodeS(imm: u12, rs2: u5, rs1: u5, funct3: u3, opcode: u7) u32 {
    return @bitCast(packed struct { opcode: u7, imm_4_0: u5, funct3: u3, rs1: u5, rs2: u5, imm_11_5: u7 }{
        .opcode = opcode,
        .imm_4_0 = @truncate(imm),
        .funct3 = funct3,
        .rs1 = rs1,
        .rs2 = rs2,
        .imm_11_5 = @truncate(imm >> 5),
    });
}

fn encodeB(imm: u13, rs2: u5, rs1: u5, funct3: u3, opcode: u7) u32 {
    return @bitCast(packed struct { opcode: u7, imm_11: u1, imm_4_1: u4, funct3: u3, rs1: u5, rs2: u5, imm_10_5: u6, imm_12: u1 }{
        .opcode = opcode,
        .imm_11 = @truncate(imm >> 11),
        .imm_4_1 = @truncate(imm >> 1),
        .funct3 = funct3,
        .rs1 = rs1,
        .rs2 = rs2,
        .imm_10_5 = @truncate(imm >> 5),
        .imm_12 = @truncate(imm >> 12),
    });
}

fn encodeU(imm: u20, rd: u5, opcode: u7) u32 {
    return @bitCast(packed struct { opcode: u7, rd: u5, imm: u20 }{
        .opcode = opcode,
        .rd = rd,
        .imm = imm,
    });
}

fn encodeJ(imm: u21, rd: u5, opcode: u7) u32 {
    return @bitCast(packed struct { opcode: u7, rd: u5, imm_19_12: u8, imm_11: u1, imm_10_1: u10, imm_20: u1 }{
        .opcode = opcode,
        .rd = rd,
        .imm_19_12 = @truncate(imm >> 12),
        .imm_11 = @truncate(imm >> 11),
        .imm_10_1 = @truncate(imm >> 1),
        .imm_20 = @truncate(imm >> 20),
    });
}

fn signedToU12(imm: i12) u12 {
    return @bitCast(imm);
}

fn signedToU13(imm: i13) u13 {
    return @bitCast(imm);
}

fn signedToU21(imm: i21) u21 {
    return @bitCast(imm);
}

fn writeInst(mem: []u8, offset: usize, inst: u32) void {
    std.mem.writeInt(u32, mem[offset..][0..4], inst, .little);
}

fn writeInst16(mem: []u8, offset: usize, inst: u16) void {
    std.mem.writeInt(u16, mem[offset..][0..2], inst, .little);
}

fn testMem() [256]u8 {
    return [_]u8{0} ** 256;
}
