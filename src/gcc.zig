const std = @import("std");
const errors = @import("errors.zig");
const FlagTranslationError = errors.FlagTranslationError;
const ConversionError = errors.ConversionError;

pub const Fpu = struct {
    name: []const u8,

    /// Because of backwards compatibility, when converting from a Zig target,
    /// need to know which fpu to "prefer" since multiple FPUs "could" match
    priority: u8,
    zig_features: []const std.Target.arm.Feature,
    pub fn fromString(str: []const u8) !Fpu {
        inline for (@typeInfo(fpu).Struct.decls) |decl| {
            if (std.mem.eql(u8, str, decl.name)) {
                return @field(fpu, decl.name);
            }
        }
        return FlagTranslationError.InvalidFpu;
    }

    pub fn eql(self: Fpu, other: Fpu) bool {
        if (!std.mem.eql(u8, self.name, other.name)) return false;
        if (self.priority != other.priority) return false;
        if (self.zig_features.len != other.zig_features.len) return false;
        for (self.zig_features, other.zig_features) |fta, ftb| {
            if (fta != ftb) return false;
        }
        return true;
    }
};

const ArmFeature = std.Target.arm.Feature;

/// Corresponds to valid options for "-mfpu=" flag
///
/// When converting from a Zig target, will "prefer" fpus
/// in the following order to make mapping to/from zig targets
/// equal in both directions:
/// - crypto + neon + fp-armv8 variants
/// - neon + fp-armv8 variants
/// - fp-armv8 variants/vfpv5 variants
/// - neon + vfpv4 variants
/// - vfpv4 variants
/// - neon + vfpv3 variants
/// - vfpv3 variants
/// - vfpv3
/// - vfp
pub const fpu = struct {
    pub const @"crypto-neon-fp-armv8": Fpu = .{ .name = "crypto-neon-fp-armv8", .priority = 0, .zig_features = &.{ ArmFeature.crypto, ArmFeature.neon, ArmFeature.fp_armv8 } };

    pub const @"neon-fp-armv8": Fpu = .{ .name = "neon-fp-armv8", .priority = 1, .zig_features = &.{ ArmFeature.neon, ArmFeature.fp_armv8 } };
    pub const @"neon-fp16": Fpu = .{ .name = "neon-fp16", .priority = 1, .zig_features = &.{ ArmFeature.neon, ArmFeature.fp_armv8d16 } };

    pub const @"fp-armv8": Fpu = .{ .name = "fp-armv8", .priority = 2, .zig_features = &.{ArmFeature.fp_armv8} };
    pub const @"fpv5-d16": Fpu = .{ .name = "fpv5-d16", .priority = 2, .zig_features = &.{ArmFeature.fp_armv8d16} };
    pub const @"fpv5-sp-d16": Fpu = .{ .name = "fpv5-sp-d16", .priority = 2, .zig_features = &.{ArmFeature.fp_armv8d16sp} };

    pub const @"neon-vfpv4": Fpu = .{ .name = "neon-vfpv4", .priority = 3, .zig_features = &.{ ArmFeature.neon, ArmFeature.vfp4 } };

    pub const vfpv4: Fpu = .{ .name = "vfpv4", .priority = 4, .zig_features = &.{ArmFeature.vfp4} };
    pub const @"vfpv4-d16": Fpu = .{ .name = "vfpv4-d16", .priority = 4, .zig_features = &.{ArmFeature.vfp4d16} };
    pub const @"fpv4-sp-d16": Fpu = .{ .name = "fpv4-sp-d16", .priority = 4, .zig_features = &.{ArmFeature.vfp4d16sp} };

    pub const @"neon-vfpv3": Fpu = .{ .name = "neon-vfpv3", .priority = 5, .zig_features = &.{ ArmFeature.neon, ArmFeature.vfp3 } };
    pub const neon = .{ .name = "neon", .priority = 5, .zig_features = @"neon-vfpv3".zig_features }; // Alias for neon-vfpv3

    pub const vfp3: Fpu = .{ .name = "vfp3", .priority = 6, .zig_features = &.{ArmFeature.vfp3} };
    pub const vfpv3 = .{ .name = "vfpv3", .priority = 6, .zig_features = vfp3.zig_features }; // Alias for vfp3
    pub const @"vfpv3-d16": Fpu = .{ .name = "vfpv3-d16", .priority = 6, .zig_features = &.{ArmFeature.vfp3d16} };
    pub const @"vfpv3-d16-fp16": Fpu = .{ .name = "vfpv3-d16-fp16", .priority = 6, .zig_features = &.{ArmFeature.vfp3d16sp} };
    pub const @"vfpv3-fp16": Fpu = .{ .name = "vfpv3-fp16", .priority = 6, .zig_features = &.{ArmFeature.vfp3sp} };

    pub const vfpv2: Fpu = .{ .name = "vfpv2", .priority = 7, .zig_features = &.{ArmFeature.vfp2} };
    pub const vfp = .{ .name = "vfp", .priority = 8, .zig_features = vfpv2.zig_features }; // Alias for vfpv2
};

const ZigCpuModel = std.Target.Cpu.Model;

pub const Cpu = struct {
    name: []const u8,
    zig_cpu_model: *const ZigCpuModel,
    compatible_fpus: []const Fpu = &.{},

    pub fn fromString(mcpu: []const u8) FlagTranslationError!Cpu {
        inline for (@typeInfo(cpu).Struct.decls) |decl| {
            if (std.mem.eql(u8, mcpu, decl.name)) {
                return @field(cpu, decl.name);
            }
        }
        return FlagTranslationError.InvalidCpu;
    }

    pub fn fromZigTarget(target: std.Target) ConversionError!Cpu {
        if (target.cpu.model.llvm_name) |llvm_name| {
            return Cpu.fromString(llvm_name) catch ConversionError.UnsupportedCpu;
        } else {
            return ConversionError.UnsupportedCpu;
        }
    }

    pub fn printInfo(self: Cpu, writer: anytype) !void {
        try writer.print("CPU: {s: <15} | Float ABIS: ", .{self.name});

        if (self.compatible_fpus.len > 0) {
            try writer.print("soft,softfp,hard | Fpu Types: ", .{});
            for (self.compatible_fpus, 0..) |fpu_val, idx| {
                if (idx == self.compatible_fpus.len - 1) {
                    try writer.print("{s}", .{fpu_val.name});
                } else {
                    try writer.print("{s},", .{fpu_val.name});
                }
            }
        } else {
            try writer.print("soft             | Fpu Types: (none)", .{});
        }
        try writer.print("\n", .{});
    }

    pub fn eql(self: Cpu, other: Cpu) bool {
        if (!std.mem.eql(u8, self.name, other.name)) return false;
        if (self.zig_cpu_model != other.zig_cpu_model) return false;
        if (self.compatible_fpus.len != other.compatible_fpus.len) return false;
        for (self.compatible_fpus, other.compatible_fpus) |fpua, fpub| {
            if (!fpua.eql(fpub)) return false;
        }
        return true;
    }
};

test "Cpu from Zig Target" {
    @setEvalBranchQuota(10000);
    var query: std.Target.Query = .{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabihf,
        .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m7 },
    };

    // Extremely contrived, but fun way to test that all CPUs supported can be converted from a Zig target :)
    // Potentially useful in the future if we end up checking more than cpu arch + llvm_name
    inline for (@typeInfo(cpu).Struct.decls) |decl| {
        inline for (@typeInfo(std.Target.arm.cpu).Struct.decls) |zig_decl| {
            if (@field(std.Target.arm.cpu, zig_decl.name).llvm_name) |llvm_name| {
                if (std.mem.eql(u8, decl.name, llvm_name)) {
                    query.cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &@field(std.Target.arm.cpu, zig_decl.name) };
                    const target = try std.zig.system.resolveTargetQuery(query);
                    try std.testing.expectEqualDeep(@field(cpu, decl.name), Cpu.fromZigTarget(target));
                }
            }
        }
    }
}

// fn enumFieldName(T: type, enum_val: T) []const u8 {
//     inline for (std.meta.fields(T)) |enum_field| {
//         if (enum_field.value == @intFromEnum(enum_val)) {
//             return enum_field.name;
//         }
//     }
//     unreachable;
// }

/// Corresponds to valid options for "-mcpu=" flag and maps to Zig equivalent target CPU + acceptable FPU flags
pub const cpu = struct {
    const ArmCpu = std.Target.arm.cpu;

    // Armv6-M Cores:
    pub const @"cortex-m0" = Cpu{
        .name = "cortex-m0",
        .zig_cpu_model = &ArmCpu.cortex_m0,
        .compatible_fpus = &.{},
    };
    pub const @"cortex-m0plus" = Cpu{
        .name = "cortex-m0plus",
        .zig_cpu_model = &ArmCpu.cortex_m0plus,
        .compatible_fpus = &.{},
    };
    pub const @"cortex-m1" = Cpu{
        .name = "cortex-m1",
        .zig_cpu_model = &ArmCpu.cortex_m1,
        .compatible_fpus = &.{},
    };

    // Armv7-M Cores:
    pub const @"cortex-m3" = Cpu{
        .name = "cortex-m3",
        .zig_cpu_model = &ArmCpu.cortex_m3,
        .compatible_fpus = &.{},
    };

    // Armv7-EM Cores:
    pub const @"cortex-m4" = Cpu{
        .name = "cortex-m4",
        .zig_cpu_model = &ArmCpu.cortex_m4,
        .compatible_fpus = &.{fpu.@"fpv4-sp-d16"},
    };
    pub const @"cortex-m7" = Cpu{
        .name = "cortex-m7",
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
        .name = "cortex-m23",
        .zig_cpu_model = &ArmCpu.cortex_m23,
        .compatible_fpus = &.{},
    };

    // Armv8-M Mainline Cores:
    pub const @"cortex-m33" = Cpu{
        .name = "cortex-m33",
        .zig_cpu_model = &ArmCpu.cortex_m33,
        .compatible_fpus = &.{ fpu.@"fp-armv8", fpu.@"neon-fp-armv8" },
    };

    pub const @"cortex-m35p" = Cpu{
        .name = "cortex-m35p",
        .zig_cpu_model = &ArmCpu.cortex_m35p,
        .compatible_fpus = &.{ fpu.@"fp-armv8", fpu.@"neon-fp-armv8" },
    };

    pub const @"cortex-m55" = Cpu{
        .name = "cortex-m55",
        .zig_cpu_model = &ArmCpu.cortex_m55,
        .compatible_fpus = &.{ fpu.@"fp-armv8", fpu.@"neon-fp-armv8" },
    };

    // Armv8.1-M Mainline Cores:
    pub const @"cortex-m85" = Cpu{
        .name = "cortex-m85",
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
