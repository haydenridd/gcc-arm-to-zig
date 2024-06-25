const std = @import("std");
const testing = std.testing;
const gcc = @import("gcc.zig");
const errors = @import("errors.zig");
const ConversionError = errors.ConversionError;
const FlagTranslationError = errors.FlagTranslationError;

/// Represents an arm GCC target using fields familiar to those using arm-none-eabi-gcc to compile projects.
pub const Target = struct {
    /// Corresponds to -mcpu flag, select using cpu.[flag_value]
    cpu: gcc.Cpu,

    /// Set to .thumb if using -mthumb, or to .arm if using -marm
    instruction_set: gcc.InstructionSet = .thumb,

    /// Set to .little if using -mlittle-endian (default) or .big if using -mbig-endian
    endianness: gcc.Endianness = .little,

    /// Corresponds to -mfloat-abi flag
    float_abi: gcc.FloatAbi = .soft,

    /// Not neccessary when using "soft" float_abi, corresponds to -mfpu flag
    fpu: ?gcc.Fpu = null,

    fn toArmFeatureSet(self: Target) ConversionError!std.Target.Cpu.Feature.Set {

        // Currently space for 16 features is plenty
        var cpu_features = std.BoundedArray(std.Target.arm.Feature, 16).init(0) catch unreachable;

        if (self.float_abi == .softfp)
            cpu_features.append(std.Target.arm.Feature.soft_float) catch return ConversionError.FeatureOverflow;

        if (self.fpu) |fpu| {
            cpu_features.appendSlice(fpu.zig_features) catch return ConversionError.FeatureOverflow;
        }

        return std.Target.arm.featureSet(cpu_features.slice());
    }

    fn validateFpuSettings(self: Target) ConversionError!void {

        // Soft float ABI can't have an FPU specified
        if (self.float_abi == .soft) {
            if (self.fpu) |_| {
                return ConversionError.FpuSpecifiedForSoftFloatAbi;
            }
        }
        if (self.fpu) |fpu| {
            if (self.cpu.compatible_fpus.len == 0) return ConversionError.NoFpuOnCpu;
            for (self.cpu.compatible_fpus) |compat_fpu| {
                if (std.mem.eql(std.Target.arm.Feature, compat_fpu.zig_features, fpu.zig_features)) return;
            }
            return ConversionError.IncompatibleFpuForCpu;
        }
    }

    /// Produces a target query for use with b.resolveTargetQuery()
    pub fn toTargetQuery(self: Target) ConversionError!std.Target.Query {
        try self.validateFpuSettings();

        const cpu_arch: std.Target.Cpu.Arch = if (self.instruction_set == gcc.InstructionSet.thumb)
            if (self.endianness == .little) .thumb else .thumbeb
        else if (self.endianness == .little) .arm else .armeb;

        return std.Target.Query{
            .cpu_arch = cpu_arch,
            .os_tag = .freestanding,
            .abi = if (self.float_abi == .soft) .eabi else .eabihf,
            .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = self.cpu.zig_cpu_model },
            .cpu_features_add = try self.toArmFeatureSet(),
        };
    }

    /// Create directly from flag string values
    pub fn fromFlags(mcpu: ?[]const u8, mfloat_abi: ?[]const u8, mfpu: ?[]const u8, mthumb: bool, marm: bool) !Target {
        const mcpu_str =
            if (mcpu) |v| v else return FlagTranslationError.MissingCpu;

        const cpu = gcc.Cpu.fromString(mcpu_str) catch |err| return err;
        const thumb = if (mthumb) true else if (marm) false else true;
        const FloatAbi = gcc.FloatAbi;
        const float_abi: FloatAbi = val: {
            if (mfloat_abi) |float_abi_str| {
                if (std.meta.stringToEnum(FloatAbi, float_abi_str)) |v| {
                    break :val v;
                } else {
                    return FlagTranslationError.InvalidFloatAbi;
                }
            } else {
                break :val .soft;
            }
        };

        const Fpu = gcc.Fpu;

        const fpu: ?Fpu = val: {
            if (mfpu) |mfpu_str| {
                break :val gcc.Fpu.fromString(mfpu_str) catch return FlagTranslationError.InvalidFpu;
            } else if (float_abi != .soft) {
                return FlagTranslationError.MissingFpu;
            } else {
                break :val null;
            }
        };

        return .{
            .cpu = cpu,
            .instruction_set = if (thumb) .thumb else .arm,
            .float_abi = float_abi,
            .fpu = fpu,
        };
    }

    /// Given a Zig target, produce the corresponding "GCC target", or error if no matching one is found
    pub fn fromZigTarget(target: std.Target) ConversionError!Target {
        const cpu = try gcc.Cpu.fromZigTarget(target);
        const instruction_set: gcc.InstructionSet = switch (target.cpu.arch) {
            .thumb, .thumbeb => .thumb,
            .arm, .armeb => .arm,
            else => return ConversionError.UnsupportedCpu,
        };
        const endianness: gcc.Endianness = switch (target.cpu.arch) {
            .thumb, .arm => .little,
            .thumbeb, .armeb => .big,
            else => return ConversionError.UnsupportedCpu,
        };

        // Iterate through all FPUs, if it contains all required feautures, pick that one
        var fpu: ?gcc.Fpu = null;
        inline for (@typeInfo(gcc.fpu).Struct.decls) |decl| {
            var valid = true;
            for (@field(gcc.fpu, decl.name).zig_features) |feature| {
                if (!std.Target.arm.featureSetHas(target.cpu.features, feature)) {
                    valid = false;
                    break;
                }
            }
            if (valid) {
                if (fpu) |v| {
                    const tmp_fpu = @field(gcc.fpu, decl.name);
                    // Priority system makes sure fpus that are a subset of other fpus aren't mistakenly chosen
                    if (tmp_fpu.priority < v.priority) {
                        fpu = tmp_fpu;
                    }
                } else {
                    fpu = @field(gcc.fpu, decl.name);
                }
            }
        }

        // Check for special feature indicating "softfp" abi
        const float_abi: gcc.FloatAbi = val: {
            if (fpu) |fpu_val| {
                // Check FPU is compatible with this CPU
                var compatible = false;
                for (cpu.compatible_fpus) |compat_fpu| {
                    if (std.mem.eql(u8, compat_fpu.name, fpu_val.name)) {
                        compatible = true;
                        break;
                    }
                }
                if (!compatible) return ConversionError.IncompatibleFpuForCpu;
                break :val if (std.Target.arm.featureSetHas(target.cpu.features, .soft_float)) .softfp else .hard;
            } else {
                break :val .soft;
            }
        };

        return .{
            .cpu = cpu,
            .instruction_set = instruction_set,
            .endianness = endianness,
            .float_abi = float_abi,
            .fpu = fpu,
        };
    }

    pub fn eql(self: Target, other: Target) bool {
        if (self.fpu) |sfpu| {
            if (other.fpu) |ofpu| {
                if (!sfpu.eql(ofpu)) return false;
            } else {
                return false;
            }
        } else if (other.fpu) |_| {
            return false;
        }
        return (self.endianness == other.endianness) and (self.float_abi == other.float_abi) and (self.instruction_set == other.instruction_set) and self.cpu.eql(other.cpu);
    }
};

test "Target Conversion" {
    try std.testing.expectEqualDeep(Target{
        .cpu = gcc.cpu.@"cortex-m7",
        .endianness = .little,
        .float_abi = .hard,
        .instruction_set = .thumb,
        .fpu = gcc.fpu.@"fpv5-sp-d16",
    }, try Target.fromZigTarget(
        try std.zig.system.resolveTargetQuery(.{
            .cpu_arch = .thumb,
            .os_tag = .freestanding,
            .abi = .eabihf,
            .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m7 },
            .cpu_features_add = std.Target.arm.featureSet(&[_]std.Target.arm.Feature{std.Target.arm.Feature.fp_armv8d16sp}),
        }),
    ));

    try std.testing.expectEqualDeep(Target{
        .cpu = gcc.cpu.@"cortex-m7",
        .endianness = .little,
        .float_abi = .softfp,
        .instruction_set = .thumb,
        .fpu = gcc.fpu.@"fpv5-sp-d16",
    }, try Target.fromZigTarget(
        try std.zig.system.resolveTargetQuery(.{
            .cpu_arch = .thumb,
            .os_tag = .freestanding,
            .abi = .eabihf,
            .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m7 },
            .cpu_features_add = std.Target.arm.featureSet(&[_]std.Target.arm.Feature{ std.Target.arm.Feature.fp_armv8d16sp, std.Target.arm.Feature.soft_float }),
        }),
    ));

    try std.testing.expectEqualDeep(Target{
        .cpu = gcc.cpu.@"cortex-m55",
        .endianness = .little,
        .float_abi = .hard,
        .instruction_set = .thumb,
        .fpu = gcc.fpu.@"fp-armv8",
    }, try Target.fromZigTarget(
        try std.zig.system.resolveTargetQuery(.{
            .cpu_arch = .thumb,
            .os_tag = .freestanding,
            .abi = .eabihf,
            .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m55 },
            .cpu_features_add = std.Target.arm.featureSet(&[_]std.Target.arm.Feature{std.Target.arm.Feature.fp_armv8}),
        }),
    ));

    try std.testing.expectEqualDeep(Target{
        .cpu = gcc.cpu.@"cortex-m55",
        .endianness = .little,
        .float_abi = .hard,
        .instruction_set = .thumb,
        .fpu = gcc.fpu.@"neon-fp-armv8",
    }, try Target.fromZigTarget(
        try std.zig.system.resolveTargetQuery(.{
            .cpu_arch = .thumb,
            .os_tag = .freestanding,
            .abi = .eabihf,
            .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m55 },
            .cpu_features_add = std.Target.arm.featureSet(&[_]std.Target.arm.Feature{ std.Target.arm.Feature.fp_armv8, std.Target.arm.Feature.neon }),
        }),
    ));

    try std.testing.expectError(ConversionError.IncompatibleFpuForCpu, Target.fromZigTarget(try std.zig.system.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabihf,
        .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m0 },
        .cpu_features_add = std.Target.arm.featureSet(&[_]std.Target.arm.Feature{ std.Target.arm.Feature.fp_armv8, std.Target.arm.Feature.neon }),
    })));
}

test "translateFlags" {
    const target: Target = .{
        .cpu = gcc.cpu.@"cortex-m7",
        .instruction_set = .thumb,
        .float_abi = .hard,
        .fpu = gcc.fpu.@"fpv5-sp-d16",
    };

    try std.testing.expectEqualDeep(target, try Target.fromFlags("cortex-m7", "hard", "fpv5-sp-d16", true, false));
    try std.testing.expectError(FlagTranslationError.MissingCpu, Target.fromFlags(null, "hard", "fpv5-sp-d16", true, false));
    try std.testing.expectError(FlagTranslationError.InvalidCpu, Target.fromFlags("doinkus", "hard", "fpv5-sp-d16", true, false));
    try std.testing.expectError(FlagTranslationError.InvalidFloatAbi, Target.fromFlags("cortex-m7", "doinkus", "fpv5-sp-d16", true, false));
    try std.testing.expectError(FlagTranslationError.MissingFpu, Target.fromFlags("cortex-m7", "hard", null, true, false));
    try std.testing.expectError(FlagTranslationError.InvalidFpu, Target.fromFlags("cortex-m7", "hard", "doinkus", true, false));
}

test "Valid Conversion" {
    const some_query = std.Target.Query{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabihf,
        .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m7 },
        .cpu_features_add = std.Target.arm.featureSet(&[_]std.Target.arm.Feature{std.Target.arm.Feature.fp_armv8d16sp}),
    };
    const my_target: Target = .{ .cpu = gcc.cpu.@"cortex-m7", .instruction_set = .thumb, .float_abi = .hard, .fpu = gcc.fpu.@"fpv5-sp-d16" };
    try std.testing.expectEqualDeep(some_query, try my_target.toTargetQuery());
}

test "Invalid Conversion" {

    // Fpu w/ Soft
    var target_query = Target{ .cpu = gcc.cpu.@"cortex-m0", .float_abi = .soft, .instruction_set = .thumb, .fpu = gcc.fpu.@"fp-armv8" };
    try std.testing.expectError(ConversionError.FpuSpecifiedForSoftFloatAbi, target_query.toTargetQuery());

    // Chip w/o FPU
    target_query = Target{ .cpu = gcc.cpu.@"cortex-m0", .float_abi = .hard, .instruction_set = .thumb, .fpu = gcc.fpu.@"fp-armv8" };
    try std.testing.expectError(ConversionError.NoFpuOnCpu, target_query.toTargetQuery());

    // Unsupported FPU Option
    target_query = Target{ .cpu = gcc.cpu.@"cortex-m7", .float_abi = .hard, .instruction_set = .thumb, .fpu = gcc.fpu.vfp };
    try std.testing.expectError(ConversionError.IncompatibleFpuForCpu, target_query.toTargetQuery());
}

test "Equality" {
    const targeta: Target = .{
        .cpu = gcc.cpu.@"cortex-m7",
        .endianness = .little,
        .instruction_set = .thumb,
        .float_abi = .hard,
        .fpu = gcc.fpu.@"fpv5-sp-d16",
    };

    var targetb: Target = .{
        .cpu = gcc.cpu.@"cortex-m7",
        .endianness = .little,
        .instruction_set = .thumb,
        .float_abi = .hard,
        .fpu = gcc.fpu.@"fpv5-sp-d16",
    };

    try std.testing.expect(targeta.eql(targetb));
    targetb.fpu = gcc.fpu.@"fpv5-d16";
    try std.testing.expect(!targeta.eql(targetb));
}
