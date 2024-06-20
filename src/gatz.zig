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

fn showHelp() anyerror!void {
    var stdout_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = stdout_buffered.writer();
    try stdout.writeAll("Usage: ");
    try stdout.writeAll(program_name);
    try stdout.writeAll(
        \\ [command] [args]...
        \\
    );
    for (sub_commands) |sub_command|
        try sub_command.help(stdout);
    try stdout_buffered.flush();
}

pub fn checkCompatibility(zig_target: std.Target) errors.ConversionError!void {
    _ = try Cpu.fromZigTarget(zig_target);
}

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

    const zig_targeta = try std.zig.system.resolveTargetQuery(try targeta.toTargetQuery());
    const zig_targetb = try std.zig.system.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabi,
        .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m4 },
    });

    try std.testing.expect(targetWithin(zig_targeta, &.{ targeta, targetb }));
    try std.testing.expect(!targetWithin(zig_targetb, &.{ targeta, targetb }));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Grab top level command
    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next();

    const command_str = args_iter.next() orelse "help";
    for (sub_commands) |sub_command| {
        if (std.mem.eql(u8, command_str, sub_command.name)) {
            try sub_command.func(sub_command, allocator, &args_iter);
            return;
        }
    }

    return showHelp();
}

const program_name = "gatz";

const SubCommand = struct {
    name: []const u8,
    func: *const fn (SubCommand, std.mem.Allocator, *std.process.ArgIterator) anyerror!void,
    description: []const u8,

    fn help(sub_command: SubCommand, writer: anytype) !void {
        const spaces = " " ** 20;
        try writer.writeAll("    ");
        try writer.writeAll(sub_command.name);
        try writer.writeAll(spaces[sub_command.name.len..]);
        try writer.writeAll(sub_command.description);
        try writer.writeAll("\n");
    }

    fn usageOut(sub_command: SubCommand, p: []const clap.Param(clap.Help)) !void {
        var stdout_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
        try sub_command.usage(stdout_buffered.writer(), p);
        try stdout_buffered.flush();
    }

    fn usageErr(sub_command: SubCommand, p: []const clap.Param(clap.Help), prepend_msg: []const u8) !void {
        var stderr_buffered = std.io.bufferedWriter(std.io.getStdErr().writer());
        if (prepend_msg.len > 0) {
            _ = try stderr_buffered.write(prepend_msg);
        }
        try sub_command.usage(stderr_buffered.writer(), p);
        try stderr_buffered.flush();
    }

    fn usage(sub_command: SubCommand, stream: anytype, p: []const clap.Param(clap.Help)) !void {
        try stream.print("Usage: {s} {s} ", .{ program_name, sub_command.name });
        try clap.usage(stream, clap.Help, p);
        try stream.writeAll("\n\n");
        try stream.writeAll(sub_command.description);
        try stream.writeAll(
            \\
            \\
            \\Options:
            \\
        );
        try clap.help(stream, clap.Help, p, .{});
    }
};

fn cmdTranslate(
    sub_command: SubCommand,
    allocator: std.mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\--mcpu <str>            GCC cpu target flag         (Required)
        \\--mfloat-abi <str>      "hard", "softfp", or "soft" (Optional - default "soft")
        \\--mfpu <str>            GCC floating point ISA flag (Required with "hard" or "softfp")
        \\--mthumb                Use thumb instruction set   (Optional - default enabled)
        \\--marm                  Use arm instruction set     (Optional - default disabled)
        \\
    );

    var diag = clap.Diagnostic{};
    var parsed = clap.parseEx(clap.Help, &params, clap.parsers.default, args_iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer parsed.deinit();

    if (parsed.args.help != 0)
        return sub_command.usageOut(&params);

    var stderr_buffered = std.io.bufferedWriter(std.io.getStdErr().writer());
    const stderr = stderr_buffered.writer();
    const FlagTranslationError = errors.FlagTranslationError;
    const target = Target.fromFlags(parsed.args.mcpu, parsed.args.@"mfloat-abi", parsed.args.mfpu, parsed.args.mthumb > 0, parsed.args.marm > 0) catch |err| switch (err) {
        FlagTranslationError.MissingCpu => return sub_command.usageErr(&params, "--mcpu argument required\n"),
        FlagTranslationError.InvalidCpu => {
            try stderr.print("--mcpu={?s} is not a valid CPU, see info command for valid CPUs\n", .{parsed.args.mcpu});
            try stderr_buffered.flush();
            return;
        },
        FlagTranslationError.InvalidFloatAbi => {
            try stderr.print("--mfloat-abi={?s} is not a valid float abi, valid options are \"hard\", \"softfp\", and \"soft\"\n", .{parsed.args.@"mfloat-abi"});
            try stderr_buffered.flush();
            return;
        },
        FlagTranslationError.MissingFpu => return sub_command.usageErr(&params, "--mfpu is required if --mfloat-abi!=soft\n"),
        FlagTranslationError.InvalidFpu => {
            try stderr.print("--mfpu={?s} is not a valid FPU, see info command for valid FPUs\n", .{parsed.args.mfpu});
            try stderr_buffered.flush();
            return;
        },
    };
    const query = try target.toTargetQuery();
    const zig_triple = try query.zigTriple(allocator);
    defer allocator.free(zig_triple);

    const zig_cpu_str = try query.serializeCpuAlloc(allocator);
    defer allocator.free(zig_cpu_str);

    var stdout_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = stdout_buffered.writer();
    try stdout.print("Translated `zig build` options: -Dtarget={s} -Dcpu={s}\n", .{ zig_triple, zig_cpu_str });
    try stdout_buffered.flush();
}

fn cmdInfo(
    sub_command: SubCommand,
    allocator: std.mem.Allocator,
    args_iter: *std.process.ArgIterator,
) anyerror!void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\--mcpu <str>            Filters to only one cpu target (Optional)
        \\
    );

    var diag = clap.Diagnostic{};
    var parsed = clap.parseEx(clap.Help, &params, clap.parsers.default, args_iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer parsed.deinit();

    if (parsed.args.help != 0)
        return sub_command.usageOut(&params);

    var stderr_buffered = std.io.bufferedWriter(std.io.getStdErr().writer());
    const stderr = stderr_buffered.writer();
    const cpu_maybe: ?Cpu = if (parsed.args.mcpu) |mcpu_str| Cpu.fromString(mcpu_str) catch {
        try stderr.print("--mcpu={?s} is not a valid CPU, see info command for valid CPUs\n", .{parsed.args.mcpu});
        try stderr_buffered.flush();
        return;
    } else null;

    var stdout_buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = stdout_buffered.writer();

    if (cpu_maybe) |cpu_val| {
        try cpu_val.printInfo(stdout);
    } else {
        inline for (@typeInfo(cpu).Struct.decls) |decl| {
            try @field(cpu, decl.name).printInfo(stdout);
        }
    }
    try stdout_buffered.flush();
}

const sub_commands = [_]SubCommand{
    .{ .name = "translate", .func = cmdTranslate, .description = "Validate and translate GCC arm target arguments to a Zig target argument." },
    .{ .name = "info", .func = cmdInfo, .description = "Show possible compile options for valid targets." },
};
