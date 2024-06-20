const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // TODO: This is likely not expansive
    switch (target.result.cpu.arch) {
        .thumb, .thumbeb, .arm, .armeb => {},
        else => {
            std.log.err("Unsupported CPU architecture for arm-none-eabi-gcc compiler: {any}\n", .{target.result.cpu.arch});
            unreachable;
        },
    }
    const arm_gcc_newlib = b.addModule("arm_gcc_newlib", .{ .target = target, .optimize = optimize });

    // TODO: module option vs build option?

    // Try to find arm-none-eabi-gcc program at a user specified path, or PATH variable if none provided
    const arm_gcc_pgm = if (b.option([]const u8, "armgcc", "Path to arm-none-eabi-gcc compiler")) |arm_gcc_path|
        b.findProgram(&.{"arm-none-eabi-gcc"}, &.{arm_gcc_path}) catch {
            std.log.err("Couldn't find arm-none-eabi-gcc at provided path: {s}\n", .{arm_gcc_path});
            unreachable;
        }
    else
        b.findProgram(&.{"arm-none-eabi-gcc"}, &.{}) catch {
            std.log.err("Couldn't find arm-none-eabi-gcc in PATH, try manually providing the path to this executable with -Darmgcc=[path]\n", .{});
            unreachable;
        };

    // Get CPU/FPU information from target
    const llvm_cpu_name = arm_gcc_newlib.resolved_target.?.result.cpu.model.llvm_name.?;
    std.debug.print("Cpu name: {s}\n", .{llvm_cpu_name});
    // std.debug.print("FPU enabled ?: {any}\n", .{});
    inline for (std.meta.fields(std.Target.arm.Feature)) |f| {
        if (std.Target.arm.featureSetHas(arm_gcc_newlib.resolved_target.?.result.cpu.features, @enumFromInt(f.value)))
            std.debug.print("Feature: {s}\n", .{f.name});
    }

    //  Use gcc-arm-none-eabi to figure out where library paths are
    const gcc_arm_sysroot_path = std.mem.trim(u8, b.run(&.{ arm_gcc_pgm, "-print-sysroot" }), "\r\n");
    const gcc_arm_multidir_relative_path = std.mem.trim(u8, b.run(&.{ arm_gcc_pgm, "-mcpu=cortex-m7", "-mfpu=fpv5-sp-d16", "-mfloat-abi=hard", "-print-multi-directory" }), "\r\n");
    const gcc_arm_version = std.mem.trim(u8, b.run(&.{ arm_gcc_pgm, "-dumpversion" }), "\r\n");
    const gcc_arm_lib_path1 = b.fmt("{s}/../lib/gcc/arm-none-eabi/{s}/{s}", .{ gcc_arm_sysroot_path, gcc_arm_version, gcc_arm_multidir_relative_path });
    const gcc_arm_lib_path2 = b.fmt("{s}/lib/{s}", .{ gcc_arm_sysroot_path, gcc_arm_multidir_relative_path });

    // Manually add "nano" variant newlib C standard lib from arm-none-eabi-gcc library folders
    arm_gcc_newlib.addLibraryPath(.{ .cwd_relative = gcc_arm_lib_path1 });
    arm_gcc_newlib.addLibraryPath(.{ .cwd_relative = gcc_arm_lib_path2 });
    arm_gcc_newlib.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{gcc_arm_sysroot_path}) });
    arm_gcc_newlib.linkSystemLibrary("c_nano", .{});
    arm_gcc_newlib.linkSystemLibrary("m", .{});

    // // Manually include C runtime objects bundled with arm-none-eabi-gcc
    arm_gcc_newlib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crt0.o", .{gcc_arm_lib_path2}) });
    arm_gcc_newlib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crti.o", .{gcc_arm_lib_path1}) });
    arm_gcc_newlib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crtbegin.o", .{gcc_arm_lib_path1}) });
    arm_gcc_newlib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crtend.o", .{gcc_arm_lib_path1}) });
    arm_gcc_newlib.addObjectFile(.{ .cwd_relative = b.fmt("{s}/crtn.o", .{gcc_arm_lib_path1}) });
}
