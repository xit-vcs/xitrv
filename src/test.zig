const std = @import("std");
const main = @import("./main.zig");

const hello_world = @embedFile("test/bin/hello_world");

test "create cpu" {
    const allocator = std.testing.allocator;

    var mem = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer mem.deinit();
    mem.expandToCapacity();

    @memcpy(mem.items[0..hello_world.len], hello_world);

    var cpu = main.Cpu.init();
    while (true) {
        const step = try cpu.step(mem.items);
        switch (step) {
            .cont => {},
            .exit => break,
            .system => {
                switch (step.system) {
                    0 => break,
                    1 => std.debug.print("{c}", .{@as(u8, @intCast(cpu.registers[11]))}),
                    else => return error.InvalidEcall,
                }
            },
        }
    }
}
