const std = @import("std");
const main = @import("./main.zig");

test "create cpu" {
    const allocator = std.testing.allocator;

    var mem = std.ArrayList(u8).init(allocator);
    defer mem.deinit();

    _ = main.Cpu.init();
}
