const std = @import("std");
const testing = std.testing;
pub const gcc_parameters = @import("gcc_mapping.zig");

const ConversionError = error{
    UnsupportedCpu,
    FpuSpecifiedForSoftFloatAbi,
    IncompatibleFpuForCpu,
    NoFpuOnCpu,
    FeatureOverflow,
};

pub const Target = struct {
    cpu: gcc_parameters.Cpu,
    instruction_set: gcc_parameters.InstructionSet = .thumb,
    endianness: gcc_parameters.Endianness = .little,
    float_abi: gcc_parameters.FloatAbi = .soft,
    /// Not neccessary when using "soft" float_abi
    fpu: ?gcc_parameters.Fpu = null,

    fn toArmFeatureSet(self: Target) ConversionError!std.Target.Cpu.Feature.Set {

        // Currently space for 16 features is plenty
        var cpu_features = std.BoundedArray(std.Target.arm.Feature, 16).init(0) catch unreachable;

        if (self.float_abi == .softfp)
            cpu_features.append(std.Target.arm.Feature.soft_float) catch return ConversionError.FeatureOverflow;

        if (self.fpu) |fpu| {
            cpu_features.appendSlice(fpu) catch return ConversionError.FeatureOverflow;
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
                if (std.mem.eql(std.Target.arm.Feature, compat_fpu, fpu)) return;
            }
            return ConversionError.IncompatibleFpuForCpu;
        }
    }

    pub fn toTargetQuery(self: Target) ConversionError!std.Target.Query {
        try self.validateFpuSettings();

        const cpu_arch: std.Target.Cpu.Arch = if (self.instruction_set == gcc_parameters.InstructionSet.thumb)
            if (self.endianness == .little) .thumb else .thumbeb
        else if (self.endianness == .little) .arm else .armeb;

        return std.Target.Query{
            .cpu_arch = cpu_arch,
            .os_tag = .freestanding,
            .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = self.cpu.zig_cpu_model },
            .cpu_features_add = try self.toArmFeatureSet(),
        };
    }
};

test "Valid Conversion" {
    const some_query = std.Target.Query{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m7 },
        .cpu_features_add = std.Target.arm.featureSet(&[_]std.Target.arm.Feature{std.Target.arm.Feature.fp_armv8d16sp}),
    };
    const my_target: Target = .{ .cpu = gcc_parameters.cpu.@"cortex-m7", .instruction_set = .thumb, .float_abi = .hard, .fpu = gcc_parameters.fpu.@"fpv5-sp-d16" };
    try std.testing.expectEqualDeep(some_query, try my_target.toTargetQuery());
}

test "Invalid Conversion" {

    // Fpu w/ Soft
    var target_query = Target{ .cpu = gcc_parameters.cpu.@"cortex-m0", .float_abi = .soft, .instruction_set = .thumb, .fpu = gcc_parameters.fpu.@"fp-armv8" };
    try std.testing.expectError(ConversionError.FpuSpecifiedForSoftFloatAbi, target_query.toTargetQuery());

    // Chip w/o FPU
    target_query = Target{ .cpu = gcc_parameters.cpu.@"cortex-m0", .float_abi = .hard, .instruction_set = .thumb, .fpu = gcc_parameters.fpu.@"fp-armv8" };
    try std.testing.expectError(ConversionError.NoFpuOnCpu, target_query.toTargetQuery());

    // Unsupported FPU Option
    target_query = Target{ .cpu = gcc_parameters.cpu.@"cortex-m7", .float_abi = .hard, .instruction_set = .thumb, .fpu = gcc_parameters.fpu.vfp };
    try std.testing.expectError(ConversionError.IncompatibleFpuForCpu, target_query.toTargetQuery());
}
