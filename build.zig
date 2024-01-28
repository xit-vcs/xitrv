const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "xitrv",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_unit_tests.step);

    const test_exe = b.addExecutable(.{
        .name = "hello",
        .root_source_file = .{ .path = "src/test/main.zig" },
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .ofmt = .elf,
        }),
        .optimize = .ReleaseSmall,
    });
    b.installArtifact(test_exe);
}
