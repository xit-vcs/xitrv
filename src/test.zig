const std = @import("std");
const xitrv = @import("xitrv");
const Cpu = xitrv.cpu.Cpu;
const Elf = xitrv.elf.Elf;

const stack_size: usize = 2048;

test "create cpu" {
    const allocator = std.testing.allocator;

    const hello_world = @embedFile("test/bin/hello_world");

    var mem = try allocator.alloc(u8, hello_world.len + stack_size);
    defer allocator.free(mem);
    @memcpy(mem[0..hello_world.len], hello_world);

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var cpu = Cpu(.rv32).init();

    for (0..1000) |_| {
        const step = try cpu.step(mem);
        switch (step) {
            .cont => {},
            .exit => break,
            .system => {
                switch (step.system) {
                    0 => break,
                    1 => try output.append(@intCast(cpu.registers[11])),
                    else => return error.InvalidEcall,
                }
            },
        }
    } else return error.MaxStepCountExceeded;

    try std.testing.expectEqualStrings("Hello World\n", output.items);
}

test "inc" {
    const allocator = std.testing.allocator;

    const test_file = try std.fs.cwd().openFile("zig-out/lib/libtest.so", .{ .mode = .read_only });
    defer test_file.close();

    var elf = try Elf.init(allocator, test_file.reader());
    defer elf.deinit();

    const func_symbol = elf.name_to_dynsym.get("inc") orelse return error.SymbolNotFound;
    const section = elf.sections.items[func_symbol.shndx];
    const func_offset = func_symbol.value - section.addr;

    var mem = try allocator.alloc(u8, section.kind.progbits.buffer.len + stack_size);
    defer allocator.free(mem);
    @memcpy(mem[0..section.kind.progbits.buffer.len], section.kind.progbits.buffer);

    var cpu = Cpu(.rv64).init();
    cpu.pc = func_offset;
    cpu.registers[2] = section.kind.progbits.buffer.len; // stack pointer
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

test "recur" {
    const allocator = std.testing.allocator;

    const test_file = try std.fs.cwd().openFile("zig-out/lib/libtest.so", .{ .mode = .read_only });
    defer test_file.close();

    var elf = try Elf.init(allocator, test_file.reader());
    defer elf.deinit();

    const func_symbol = elf.name_to_dynsym.get("recur") orelse return error.SymbolNotFound;
    const section = elf.sections.items[func_symbol.shndx];
    const func_offset = func_symbol.value - section.addr;

    var mem = try allocator.alloc(u8, section.kind.progbits.buffer.len + stack_size);
    defer allocator.free(mem);
    @memcpy(mem[0..section.kind.progbits.buffer.len], section.kind.progbits.buffer);

    var cpu = Cpu(.rv64).init();
    cpu.pc = func_offset;
    cpu.registers[2] = section.kind.progbits.buffer.len; // stack pointer
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
