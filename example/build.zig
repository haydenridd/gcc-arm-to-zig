const std = @import("std");
const gatz = @import("gatz");
const NewlibError = gatz.newlib.Error;
pub fn build(b: *std.Build) void {

    // Allowing the user to pass whatever target they want is fine, since gatz.checkCompatibility() can be
    // used to verify this is a supported cortex-m target
    const target = b.standardTargetOptions(.{});
    gatz.checkCompatibility(target.result) catch |err| {
        std.log.err("Not compatible! See: {any}\n", .{err});
        unreachable;
    };

    // Alternatively you can declare a specific target. Note that the fields in "gatz.Target" match up
    // exactly with the arguments to their corresponding flags (-mcpu, -mthumb/-marm, -mfloat-abi, -mfpu)
    const gatz_target = gatz.Target{
        .cpu = gatz.cpu.@"cortex-m7",
        .instruction_set = .thumb,
        .endianness = .little,
        .float_abi = .hard,
        .fpu = gatz.fpu.@"fpv5-sp-d16",
    };

    // This converts our gatz "target" into an actual Zig target query
    const target_query = gatz_target.toTargetQuery() catch |err| {
        std.log.err("Something is misconfigured, see: {any}\n", .{err});
        unreachable;
    };

    // Using the normal Zig API to resolve a target query
    const alternate_target = b.resolveTargetQuery(target_query);
    _ = alternate_target;

    // You can even restrict your targets to a know set with the following
    // if (!gatz.targetWithin(target.result, .{gatz.Target{...}, gatz.Target{...}})) {
    //     // Error
    // }

    const optimize = b.standardOptimizeOption(.{});

    const executable_name = "blinky";

    const blinky_exe = b.addExecutable(.{
        .name = executable_name ++ ".elf",
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .linkage = .static,
        .single_threaded = true,
    });

    // Linking in the arm-none-eabi-gcc supplied newlib is now a single function call!
    // Automatically grabs the correct pre-built libraries based on target. Will also
    // check to make sure a compatible target is being used
    gatz.newlib.addTo(b, target, blinky_exe) catch |err| switch (err) {
        NewlibError.CompilerNotFound => {
            std.log.err("Couldn't find arm-none-eabi-gcc compiler!\n", .{});
            unreachable;
        },
        NewlibError.IncompatibleCpu => {
            std.log.err("Cpu: {s} isn't compatible with gatz!\n", .{target.result.cpu.model.name});
            unreachable;
        },
    };

    // Normal Include Paths
    blinky_exe.addIncludePath(b.path("Core/Inc"));
    blinky_exe.addIncludePath(b.path("Drivers/STM32F7xx_HAL_Driver/Inc"));
    blinky_exe.addIncludePath(b.path("Drivers/STM32F7xx_HAL_Driver/Inc/Legacy"));
    blinky_exe.addIncludePath(b.path("Drivers/CMSIS/Device/ST/STM32F7xx/Include"));
    blinky_exe.addIncludePath(b.path("Drivers/CMSIS/Include"));

    // Startup file
    blinky_exe.addAssemblyFile(b.path("startup_stm32f750xx.s"));

    // Source files
    blinky_exe.addCSourceFiles(.{
        .files = &.{
            "Core/Src/main.c",
            "Core/Src/gpio.c",
            "Core/Src/stm32f7xx_it.c",
            "Core/Src/stm32f7xx_hal_msp.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_cortex.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_rcc.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_rcc_ex.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_flash.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_flash_ex.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_gpio.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_dma.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_dma_ex.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_pwr.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_pwr_ex.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_i2c.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_i2c_ex.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_tim.c",
            "Drivers/STM32F7xx_HAL_Driver/Src/stm32f7xx_hal_tim_ex.c",
            "Core/Src/system_stm32f7xx.c",
            "Core/Src/sysmem.c",
            "Core/Src/syscalls.c",
        },
        .flags = &.{ "-Og", "-std=c11", "-DUSE_HAL_DRIVER", "-DSTM32F750xx" },
    });

    blinky_exe.link_gc_sections = true;
    blinky_exe.link_data_sections = true;
    blinky_exe.link_function_sections = true;
    blinky_exe.setLinkerScriptPath(b.path("./STM32F750N8Hx_FLASH.ld"));

    // Produce .bin file from .elf
    const bin = b.addObjCopy(blinky_exe.getEmittedBin(), .{
        .format = .bin,
    });
    bin.step.dependOn(&blinky_exe.step);
    const copy_bin = b.addInstallBinFile(bin.getOutput(), executable_name ++ ".bin");
    b.default_step.dependOn(&copy_bin.step);

    // Produce .hex file from .elf
    const hex = b.addObjCopy(blinky_exe.getEmittedBin(), .{
        .format = .hex,
    });
    hex.step.dependOn(&blinky_exe.step);
    const copy_hex = b.addInstallBinFile(hex.getOutput(), executable_name ++ ".hex");
    b.default_step.dependOn(&copy_hex.step);
    b.installArtifact(blinky_exe);
}
