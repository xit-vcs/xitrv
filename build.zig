const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xitrv = b.addModule("xitrv", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    const test_lib = b.addSharedLibrary(.{
        .name = "test",
        .root_source_file = b.path("src/test/lib.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .riscv64,
            .cpu_model = .baseline,
            .cpu_features_sub = blk: {
                // temporarily disable compressed instructions
                const FeatureSet = std.Target.Cpu.Feature.Set;
                var features = FeatureSet.empty;
                features.addFeature(@intFromEnum(std.Target.riscv.Feature.c));
                break :blk features;
            },
            .os_tag = .linux,
            .ofmt = .elf,
        }),
        .optimize = .Debug,
    });
    const install_test_lib = b.addInstallArtifact(test_lib, .{});

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("xitrv", xitrv);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.has_side_effects = true;
    run_unit_tests.step.dependOn(&install_test_lib.step);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_unit_tests.step);
}
