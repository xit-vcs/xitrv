const std = @import("std");
const Cpu = @import("./cpu.zig").Cpu;
const Elf = @import("./elf.zig").Elf;

test "create cpu" {
    const hello_world = @embedFile("test/bin/hello_world");
    const allocator = std.testing.allocator;

    var mem = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer mem.deinit();
    mem.expandToCapacity();

    @memcpy(mem.items[0..hello_world.len], hello_world);

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var cpu = Cpu(.rv32).init();
    while (true) {
        const step = try cpu.step(mem.items);
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
    }

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

    var mem = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer mem.deinit();
    mem.expandToCapacity();

    @memcpy(mem.items[0..section.kind.progbits.buffer.len], section.kind.progbits.buffer);

    var cpu = Cpu(.rv64).init();
    cpu.pc = func_offset;
    cpu.registers[1] = func_offset;
    cpu.registers[10] = 42;
    while (true) {
        const step = try cpu.step(mem.items);
        switch (step) {
            .cont => {
                if (cpu.pc == func_offset) {
                    break;
                }
            },
            .exit => break,
            .system => {
                switch (step.system) {
                    else => return error.InvalidEcall,
                }
            },
        }
    }
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

    var mem = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer mem.deinit();
    mem.expandToCapacity();

    @memcpy(mem.items[0..section.kind.progbits.buffer.len], section.kind.progbits.buffer);

    var cpu = Cpu(.rv64).init();
    cpu.pc = func_offset;
    cpu.registers[1] = func_offset;
    cpu.registers[10] = 1;
    while (true) {
        const step = try cpu.step(mem.items);
        switch (step) {
            .cont => {
                if (cpu.registers[10] >= 10) {
                    break;
                }
            },
            .exit => break,
            .system => {
                switch (step.system) {
                    else => return error.InvalidEcall,
                }
            },
        }
    }
}
