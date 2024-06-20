const std = @import("std");
pub const Fpu = []const std.Target.arm.Feature;

/// Corresponds to valid options for "-mfpu=" flag
pub const fpu = struct {
    const ArmFeatures = std.Target.arm.Feature;
    pub const @"crypto-neon-fp-armv8": Fpu = &.{ ArmFeatures.crypto, ArmFeatures.neon, ArmFeatures.fp_armv8 };
    pub const @"fp-armv8": Fpu = &.{ArmFeatures.fp_armv8};
    pub const @"neon-fp-armv8": Fpu = &.{ ArmFeatures.neon, ArmFeatures.fp_armv8 };
    pub const @"neon-fp16": Fpu = &.{ ArmFeatures.neon, ArmFeatures.fp_armv8d16 };
    pub const @"neon-vfpv3": Fpu = &.{ ArmFeatures.neon, ArmFeatures.vfp3 };
    pub const neon = @"neon-vfpv3"; // Alias for neon-vfpv3
    pub const @"neon-vfpv4": Fpu = &.{ ArmFeatures.neon, ArmFeatures.vfp4 };
    pub const vfpv2: Fpu = &.{ArmFeatures.vfp2};
    pub const vfp = vfpv2; // Alias for vfpv2
    pub const vfp3: Fpu = &.{ArmFeatures.vfp3};
    pub const vfpv3 = vfp3; // Alias for vfp3
    pub const @"vfpv3-d16": Fpu = &.{ArmFeatures.vfp3d16};
    pub const @"vfpv3-d16-fp16": Fpu = &.{ArmFeatures.vfp3d16sp};
    pub const @"vfpv3-fp16": Fpu = &.{ArmFeatures.vfp3sp};
    pub const vfpv4: Fpu = &.{ArmFeatures.vfp4};
    pub const @"vfpv4-d16": Fpu = &.{ArmFeatures.vfp4d16};
    pub const @"fpv4-sp-d16": Fpu = &.{ArmFeatures.vfp4d16sp};
    pub const @"fpv5-d16": Fpu = &.{ArmFeatures.fp_armv8d16};
    pub const @"fpv5-sp-d16": Fpu = &.{ArmFeatures.fp_armv8d16sp};
};

const ZigCpuModel = std.Target.Cpu.Model;

pub const Cpu = struct {
    zig_cpu_model: *const ZigCpuModel,
    compatible_fpus: []const Fpu = &.{},
};

/// Corresponds to valid options for "-mcpu=" flag and maps to Zig equivalent target CPU + acceptable FPU flags
pub const cpu = struct {
    const ArmCpu = std.Target.arm.cpu;

    // Armv6-M Cores:
    pub const @"cortex-m0" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m0,
        .compatible_fpus = &.{},
    };
    pub const @"cortex-m0plus" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m0plus,
        .compatible_fpus = &.{},
    };
    pub const @"cortex-m1" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m1,
        .compatible_fpus = &.{},
    };

    // Armv7-M Cores:
    pub const @"cortex-m3" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m3,
        .compatible_fpus = &.{},
    };

    // Armv7-EM Cores:
    pub const @"cortex-m4" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m4,
        .compatible_fpus = &.{fpu.@"fpv4-sp-d16"},
    };
    pub const @"cortex-m7" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m7,
        .compatible_fpus = &.{
            fpu.vfpv4,
            fpu.@"vfpv4-d16",
            fpu.@"fpv4-sp-d16",
            fpu.@"fpv5-d16",
            fpu.@"fpv5-sp-d16",
        },
    };

    // Armv8-M Baseline Cores:
    pub const @"cortex-m23" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m23,
        .compatible_fpus = &.{},
    };

    // Armv8-M Mainline Cores:
    pub const @"cortex-m33" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m33,
        .compatible_fpus = &.{ fpu.@"fp-armv8", fpu.@"neon-fp-armv8" },
    };

    pub const @"cortex-m35p" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m35p,
        .compatible_fpus = &.{ fpu.@"fp-armv8", fpu.@"neon-fp-armv8" },
    };

    pub const @"cortex-m55" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m55,
        .compatible_fpus = &.{ fpu.@"fp-armv8", fpu.@"neon-fp-armv8" },
    };

    // Armv8.1-M Mainline Cores:
    pub const @"cortex-m85" = Cpu{
        .zig_cpu_model = &ArmCpu.cortex_m85,
        .compatible_fpus = &.{ fpu.@"fp-armv8", fpu.@"neon-fp-armv8" },
    };
};

/// Corresponds to valid options for "-mfloat-abi=" flag
pub const FloatAbi = enum { hard, soft, softfp };

/// Corresponds to whether "arm" or "thumb" instruction set is used, specified with "-mthumb" or "-marm" flags, but not both!
pub const InstructionSet = enum { thumb, arm };

/// Corresponds endianness specified with "-mlittle-endian" or "-mbig-endian" flags, but not both!
pub const Endianness = enum { little, big };
