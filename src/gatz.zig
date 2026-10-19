const std = @import("std");
const clap = @import("clap");
const testing = std.testing;
const gcc = @import("gcc.zig");

pub const Cpu = gcc.Cpu;
pub const cpu = gcc.cpu;
pub const Fpu = gcc.Fpu;
pub const fpu = gcc.fpu;
pub const FloatAbi = gcc.FloatAbi;
pub const Endianness = gcc.Endianness;
pub const InstructionSet = gcc.InstructionSet;
pub const Target = @import("converter.zig").Target;
pub const errors = @import("errors.zig");

test "gatz" {
    testing.refAllDecls(@This());
}

fn showUsage(writer: *std.Io.Writer) anyerror!void {
    const usage =
        \\Usage:
        \\  gatz [-v] [-h] <command>
        \\Options:
        \\  -h            Show help
        \\  -v            Show version
        \\Available Commands:
        \\  translate [gcc args]  - Validate and translate GCC arm target arguments to a Zig target argument
        \\    Supported args:
        \\      -mcpu=<str>            GCC cpu target flag                                       (Required)
        \\      -mfloat-abi=<str>      "hard", "softfp", or "soft"                               (Optional - default "soft")
        \\      -mfpu=<str>            GCC floating point ISA flag                               (Required with "hard" or "softfp")
        \\      -mthumb                Use thumb instruction set, mutually exclusive with -marm  (Optional - default enabled)
        \\      -marm                  Use arm instruction set                                   (Optional - default disabled)
        \\  info [options]        - Show possible compile options for valid targets (defaults to all targets)
        \\    Options:
        \\      -mcpu=<str>            Filters to only one cpu target (Optional)
        \\
    ;
    try writer.writeAll(usage);
    try writer.flush();
}

/// Check that the Zig target is supported by gatz
pub fn checkCompatibility(zig_target: std.Target) errors.ConversionError!void {
    _ = try Cpu.fromZigTarget(zig_target);
}

/// Utility for checking if a provided Zig target is within a slice of possible GCC targets
pub fn targetWithin(zig_target: std.Target, gatz_targets: []const Target) bool {
    const gatz_match = Target.fromZigTarget(zig_target) catch return false;
    for (gatz_targets) |gatz_target| {
        if (gatz_target.eql(gatz_match)) return true;
    }
    return false;
}

test "targetWithin" {
    const targeta: Target = .{
        .cpu = gcc.cpu.@"cortex-m7",
        .endianness = .little,
        .instruction_set = .thumb,
        .float_abi = .hard,
        .fpu = gcc.fpu.@"fpv5-sp-d16",
    };

    const targetb: Target = .{
        .cpu = gcc.cpu.@"cortex-m0",
        .endianness = .little,
        .instruction_set = .thumb,
        .float_abi = .soft,
        .fpu = null,
    };

    const zig_targeta = try std.zig.system.resolveTargetQuery(std.testing.io, try targeta.toTargetQuery());
    const zig_targetb = try std.zig.system.resolveTargetQuery(std.testing.io, .{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabi,
        .cpu_model = std.Target.Query.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m4 },
    });

    try std.testing.expect(targetWithin(zig_targeta, &.{ targeta, targetb }));
    try std.testing.expect(!targetWithin(zig_targetb, &.{ targeta, targetb }));
}

const ParsedArgs = union(enum) {
    help,
    version,
    command: Command,

    pub fn parse(args: []const []const u8, stderr: *std.Io.Writer) !ParsedArgs {
        var i: usize = 0;
        while (i < args.len) {
            if (std.mem.eql(u8, args[i], "-v")) {
                return .version;
            } else if (std.mem.eql(u8, args[i], "-h")) {
                return .help;
            } else {
                return .{
                    .command = try Command.parse(args[i..], stderr),
                };
            }
            i += 1;
        }
        return .help;
    }
};

const Command = union(enum) {
    translate: Translate,
    info: Info,

    pub fn parse(args: []const []const u8, stderr: *std.Io.Writer) !Command {
        var i: usize = 0;
        while (i < args.len) {
            if (std.mem.eql(u8, args[i], "translate")) {
                return .{
                    .translate = try Translate.parse(args[i + 1 ..], stderr),
                };
            } else if (std.mem.eql(u8, args[i], "info")) {
                return .{
                    .info = try Info.parse(args[i + 1 ..], stderr),
                };
            } else {
                try stderr.print("Invalid command: {s}\n", .{args[i]});
                try stderr.flush();
                return error.UnknownCommand;
            }
            i += 1;
        }
        try stderr.print("No valid command in args\n", .{});
        try stderr.flush();
        return error.UnknownCommand;
    }
};

const Translate = struct {
    mcpu: []const u8,
    @"mfloat-abi": ?[]const u8 = null,
    mfpu: ?[]const u8 = null,
    mthumb: bool = false,
    marm: bool = false,

    pub fn parse(args: []const []const u8, stderr: *std.Io.Writer) !Translate {
        var i: usize = 0;

        var cpu_maybe: ?[]const u8 = null;
        var ret: Translate = .{ .mcpu = "" };
        const mcpu_delim = "-mcpu=";
        const mfpu_delim = "-mfpu=";
        const mfloat_abi_delim = "-mfloat-abi=";
        while (i < args.len) {
            if (std.mem.eql(u8, args[i], "-marm")) {
                ret.marm = true;
            } else if (std.mem.eql(u8, args[i], "-mthumb")) {
                ret.mthumb = true;
            } else if (std.mem.find(u8, args[i], mcpu_delim)) |idx| {
                if (idx != 0) {
                    try stderr.print("Malformed -mcpu argument: {s}\n", .{args[i]});
                    try stderr.flush();
                    return error.UnknownCommand;
                }
                cpu_maybe = args[i][mcpu_delim.len..];
            } else if (std.mem.find(u8, args[i], mfpu_delim)) |idx| {
                if (idx != 0) {
                    try stderr.print("Malformed -mfpu argument: {s}\n", .{args[i]});
                    try stderr.flush();
                    return error.UnknownCommand;
                }
                ret.mfpu = args[i][mfpu_delim.len..];
            } else if (std.mem.find(u8, args[i], mfloat_abi_delim)) |idx| {
                if (idx != 0) {
                    try stderr.print("Malformed -mfloat-abi argument: {s}\n", .{args[i]});
                    try stderr.flush();
                    return error.UnknownCommand;
                }
                ret.@"mfloat-abi" = args[i][mfloat_abi_delim.len..];
            } else {
                try stderr.print("Unknown flag argument: {s}\n", .{args[i]});
                try stderr.flush();
                return error.UnknownCommand;
            }
            i += 1;
        }
        if (cpu_maybe) |mcpu| {
            ret.mcpu = mcpu;
            return ret;
        } else {
            try stderr.print("-mcpu flag not provided\n", .{});
            try stderr.flush();
            return error.MissingCpu;
        }
    }

    pub fn run(translate: Translate, arena: std.mem.Allocator, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !void {
        const FlagTranslationError = errors.FlagTranslationError;
        const target = Target.fromFlags(translate.mcpu, translate.@"mfloat-abi", translate.mfpu, translate.mthumb, translate.marm) catch |err| switch (err) {
            FlagTranslationError.MissingCpu => {
                try stderr.print("-mcpu argument required\n", .{});
                try stderr.flush();
                return;
            },
            FlagTranslationError.InvalidCpu => {
                try stderr.print("-mcpu={s} is not a valid CPU, see info command for valid CPUs\n", .{translate.mcpu});
                try stderr.flush();
                return;
            },
            FlagTranslationError.InvalidFloatAbi => {
                try stderr.print("-mfloat-abi={?s} is not a valid float abi, valid options are \"hard\", \"softfp\", and \"soft\"\n", .{translate.@"mfloat-abi"});
                try stderr.flush();
                return;
            },
            FlagTranslationError.MissingFpu => {
                try stderr.writeAll("-mfpu is required if --mfloat-abi!=soft\n");
                try stderr.flush();
                return;
            },
            FlagTranslationError.InvalidFpu => {
                try stderr.print("-mfpu={?s} is not a valid FPU, see info command for valid FPUs\n", .{translate.mfpu});
                try stderr.flush();
                return;
            },
        };
        const query = try target.toTargetQuery();
        const zig_triple = try query.zigTriple(arena);
        const zig_cpu_str = try query.serializeCpuAlloc(arena);
        try stdout.print("Translated `zig build` options: -Dtarget={s} -Dcpu={s}\n", .{ zig_triple, zig_cpu_str });
        try stdout.flush();
    }
};

const Info = struct {
    mcpu: ?[]const u8 = null,

    pub fn parse(args: []const []const u8, stderr: *std.Io.Writer) !Info {
        var i: usize = 0;

        var ret: Info = .{};
        const mcpu_delim = "-mcpu=";
        while (i < args.len) {
            if (std.mem.find(u8, args[i], mcpu_delim)) |idx| {
                if (idx != 0) {
                    try stderr.print("Malformed -mcpu argument: {s}\n", .{args[i]});
                    try stderr.flush();
                    return error.UnknownCommand;
                }
                ret.mcpu = args[i][mcpu_delim.len..];
            } else {
                try stderr.print("Unknown flag argument: {s}\n", .{args[i]});
                try stderr.flush();
                return error.UnknownCommand;
            }
            i += 1;
        }
        return ret;
    }

    pub fn run(info: Info, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !void {
        const cpu_maybe: ?Cpu = if (info.mcpu) |mcpu_str| Cpu.fromString(mcpu_str) catch {
            try stderr.print("-mcpu={s} is not a valid CPU, see info command for valid CPUs\n", .{mcpu_str});
            try stderr.flush();
            return;
        } else null;

        if (cpu_maybe) |cpu_val| {
            try cpu_val.printInfo(stdout);
        } else {
            inline for (@typeInfo(cpu).@"struct".decl_names) |decl| {
                try @field(cpu, decl).printInfo(stdout);
            }
        }
        try stdout.flush();
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const parsed = try ParsedArgs.parse(args[1..], stderr);
    switch (parsed) {
        .help => try showUsage(stdout),
        .version => {
            try stdout.print("Version: {f}\n", .{@import("options").version});
        },
        .command => |cmd| {
            switch (cmd) {
                .translate => |translate| {
                    try translate.run(arena, stdout, stderr);
                },
                .info => |info| {
                    try info.run(stdout, stderr);
                },
            }
        },
    }
    try stderr.flush();
    try stdout.flush();
}
