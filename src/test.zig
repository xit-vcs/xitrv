const std = @import("std");
const main = @import("./main.zig");

const hello_world = @embedFile("test/bin/hello_world");

test "create cpu" {
    const allocator = std.testing.allocator;

    var mem = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer mem.deinit();
    mem.expandToCapacity();

    @memcpy(mem.items[0..hello_world.len], hello_world);

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var cpu = main.Cpu.init();
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

test "test lib" {
    const test_file = try std.fs.cwd().openFile("zig-out/lib/libtest.so", .{ .mode = .read_only });
    defer test_file.close();
    const meta = try test_file.metadata();
    const file_size = meta.size();
    try std.testing.expect(file_size > 0);
}
