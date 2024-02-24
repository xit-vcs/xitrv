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

    var cpu = Cpu.init();
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

test "parse elf" {
    const allocator = std.testing.allocator;
    const test_file = try std.fs.cwd().openFile("zig-out/lib/libtest.so", .{ .mode = .read_only });
    defer test_file.close();
    var elf = try Elf.init(allocator, test_file.reader());
    defer elf.deinit();
}
