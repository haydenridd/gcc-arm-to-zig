const std = @import("std");
const gatz = @import("src/gatz.zig");

// Re-export the gatz API when importing gatz in a build.zig file
pub const Cpu = gatz.Cpu;
pub const cpu = gatz.cpu;
pub const Fpu = gatz.Fpu;
pub const fpu = gatz.fpu;
pub const FloatAbi = gatz.FloatAbi;
pub const Endianness = gatz.Endianness;
pub const InstructionSet = gatz.InstructionSet;
pub const Target = gatz.Target;
pub const errors = gatz.errors;
pub const checkCompatibility = gatz.checkCompatibility;
pub const targetWithin = gatz.targetWithin;

pub const newlib = struct {
    pub const Error = error{
        CompilerNotFound,
        IncompatibleCpu,
    };

    fn addInternal(comptime just_includes_and_system_paths: bool, b: *std.Build, target: std.Build.ResolvedTarget, exe_or_lib: *std.Build.Step.Compile) Error!void {
        // Try to find arm-none-eabi-gcc program at a user specified path, or PATH variable if none provided
        const arm_gcc_pgm = if (b.option([]const u8, "armgcc", "Path to arm-none-eabi-gcc compiler")) |arm_gcc_path|
            b.findProgram(&.{"arm-none-eabi-gcc"}, &.{arm_gcc_path}) catch return Error.CompilerNotFound
        else
            b.findProgram(&.{"arm-none-eabi-gcc"}, &.{}) catch return Error.CompilerNotFound;

        // Use provided Zig target to determine specific flags to find libraries
        const gcc_target = @import("src/converter.zig").Target.fromZigTarget(target.result) catch return Error.IncompatibleCpu;
        const fpu_string = if (gcc_target.fpu) |v| b.fmt("-mfpu={s}", .{v.name}) else "";
        const float_abi_string = switch (gcc_target.float_abi) {
            .soft => "-mfloat-abi=soft",
            .softfp => "-mfloat-abi=softfp",
            .hard => "-mfloat-abi=hard",
        };

        //  Use gcc-arm-none-eabi to figure out where library paths are
        const gcc_arm_sysroot_path = std.mem.trim(u8, b.run(&.{ arm_gcc_pgm, "-print-sysroot" }), "\r\n");
        const gcc_arm_multidir_relative_path = std.mem.trim(u8, b.run(&.{ arm_gcc_pgm, b.fmt("-mcpu={s}", .{gcc_target.cpu.name}), fpu_string, float_abi_string, "-print-multi-directory" }), "\r\n");
        const gcc_arm_version = std.mem.trim(u8, b.run(&.{ arm_gcc_pgm, "-dumpversion" }), "\r\n");
        const gcc_arm_lib_path1 = b.fmt("{s}/../lib/gcc/arm-none-eabi/{s}/{s}", .{ gcc_arm_sysroot_path, gcc_arm_version, gcc_arm_multidir_relative_path });
        const gcc_arm_lib_path2 = b.fmt("{s}/lib/{s}", .{ gcc_arm_sysroot_path, gcc_arm_multidir_relative_path });

        exe_or_lib.addLibraryPath(.{ .cwd_relative = gcc_arm_lib_path1 });
        exe_or_lib.addLibraryPath(.{ .cwd_relative = gcc_arm_lib_path2 });
        exe_or_lib.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{gcc_arm_sysroot_path}) });

        if (!just_includes_and_system_paths) {
            exe_or_lib.linkSystemLibrary("c_nano");
            exe_or_lib.linkSystemLibrary("m");

            // Manually include C runtime objects bundled with arm-none-eabi-gcc
            exe_or_lib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crt0.o", .{gcc_arm_lib_path2}) });
            exe_or_lib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crti.o", .{gcc_arm_lib_path1}) });
            exe_or_lib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crtbegin.o", .{gcc_arm_lib_path1}) });
            exe_or_lib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crtend.o", .{gcc_arm_lib_path1}) });
            exe_or_lib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crtn.o", .{gcc_arm_lib_path1}) });
        }
    }

    /// Finds relevant object files/include directories/static libraries from arm-none-eabi-gcc
    /// given a target, and then adds them to the provided exe.
    ///
    /// TODO: Add user options to choose which flavor of newlib is linked in (normal vs nano)
    pub fn addTo(b: *std.Build, target: std.Build.ResolvedTarget, exe_or_lib: *std.Build.Step.Compile) Error!void {
        return addInternal(false, b, target, exe_or_lib);
    }

    /// Includes system search paths and header paths from newlib.
    /// This is a workaround to the following issue, so ideally in the future this will be unneccessary:
    /// - https://github.com/ziglang/zig/issues/20431
    ///
    pub fn addIncludeHeadersAndSystemPathsTo(b: *std.Build, target: std.Build.ResolvedTarget, exe_or_lib: *std.Build.Step.Compile) Error!void {
        return addInternal(true, b, target, exe_or_lib);
    }
};

pub fn build(b: *std.Build) void {
    _ = b.addModule("gatz", .{ .root_source_file = b.path("src/gatz.zig") });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "gatz",
        .root_source_file = b.path("src/gatz.zig"),
        .target = target,
        .optimize = optimize,
    });
    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the gatz CLI");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/gatz.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("clap", clap.module("clap"));

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_tests.step);
}
