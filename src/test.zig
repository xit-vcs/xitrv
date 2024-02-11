const std = @import("std");
const main = @import("./main.zig");

const hello_world = @embedFile("test/bin/hello_world");

test "create cpu" {
    const allocator = std.testing.allocator;

    var mem = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer mem.deinit();
    mem.expandToCapacity();

    @memcpy(mem.items[0..hello_world.len], hello_world);

    var cpu = main.Cpu.init();
    while (true) {
        switch (cpu.step(mem.items)) {
            .cont => {},
            .exit => break,
        }
    }
}
