const std = @import("std");

pub const Cpu = struct {
    registers: [32]u32,

    pub fn init() Cpu {
        return .{
            .registers = [_]u32{0} ** 32,
        };
    }
};
