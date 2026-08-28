const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const monolith_mod = b.createModule(.{
        .root_source_file = b.path("src/backtest_main.zig"),
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "monolith",
        .root_module = monolith_mod,
        .linkage = .dynamic,
    });
    b.installArtifact(lib);

    // Add backtest_main executable
    const backtest_mod = b.createModule(.{
        .root_source_file = b.path("src/backtest_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const backtest_exe = b.addExecutable(.{
        .name = "backtest_main",
        .root_module = backtest_mod,
        .target = target,
        .optimize = optimize,
    });
    backtest_exe.linkLibrary(lib);
    b.installArtifact(backtest_exe);
}
