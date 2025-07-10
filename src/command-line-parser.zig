const std = @import("std");

const Arguments = @import("arguments.zig").Arguments;
const Flags = @import("flags.zig").Flags;
const Flag = @import("flags.zig").Flag;
const FlagType = @import("flags.zig").FlagType;
const FlagValue = @import("flags.zig").FlagValue;
const Diagnostics = @import("diagnostics.zig").Diagnostics;

const ParsedFlags = @import("flags.zig").ParsedFlags;
const ParsedFlag = @import("flags.zig").ParsedFlag;

const Commands = @import("commands.zig").Commands;

pub const CommandParsingError = error{
    NoSubcommandProvided,
    SubcommandNotAddedToParentCommand,
    NoFlagsAddedToCommand,
    NoFlagValueProvided,
    FlagNotFound,
};

pub const CommandLineParser = struct {
    arguments: *Arguments,
    command_flags: ?Flags,
    diagnostics: *Diagnostics,

    pub fn init(arguments: *Arguments, command_flags: ?Flags, diagnostics: *Diagnostics) CommandLineParser {
        return .{
            .arguments = arguments,
            .command_flags = command_flags,
            .diagnostics = diagnostics,
        };
    }

    pub fn parse(
        self: *CommandLineParser,
        parsed_flags: *ParsedFlags,
        parsed_arguments: *std.ArrayList([]const u8),
        has_subcommands: bool,
    ) !void {
        var last_flag: ?Flag = null;
        while (self.arguments.next()) |argument| {
            if (Flag.looksLikeFlagName(argument)) {
                if (self.command_flags == null) {
                    return self.diagnostics.reportAndFail(.{ .NoFlagsAddedToCommand = .{
                        .parsed_flag = argument,
                    } });
                }
                if (last_flag) |flag| {
                    if (flag.flag_type == FlagType.boolean) {
                        try parsed_flags.addFlag(ParsedFlag.init(flag.name, FlagValue.type_boolean(true)));
                    } else {
                        return self.diagnostics.reportAndFail(.{ .NoFlagValueProvided = .{
                            .parsed_flag = flag.name,
                        } });
                    }
                }
                const flag_name = Flag.normalizeFlagName(argument);
                last_flag = self.command_flags.?.get(flag_name) orelse return self.diagnostics.reportAndFail(.{ .FlagNotFound = .{ .flag_name = flag_name } });
            } else if (last_flag) |flag| {
                if (flag.flag_type == FlagType.boolean) {
                    if (Flag.looksLikeBooleanFlagValue(argument)) {
                        const flag_value = try flag.toFlagValue(argument, self.diagnostics);
                        try parsed_flags.addFlag(ParsedFlag.init(flag.name, flag_value));
                        last_flag = null;
                    } else {
                        try parsed_flags.addFlag(ParsedFlag.init(flag.name, FlagValue.type_boolean(true)));
                        try parsed_arguments.append(argument);
                        last_flag = null;

                        if (has_subcommands) {
                            break;
                        }
                    }
                } else {
                    const flag_value = try flag.toFlagValue(argument, self.diagnostics);
                    try parsed_flags.addFlag(ParsedFlag.init(flag.name, flag_value));
                    last_flag = null;
                }
            } else {
                try parsed_arguments.append(argument);
                last_flag = null;

                if (has_subcommands) {
                    break;
                }
            }
        }

        if (last_flag) |flag| {
            if (flag.flag_type != FlagType.boolean) {
                return self.diagnostics.reportAndFail(.{ .NoFlagValueProvided = .{
                    .parsed_flag = flag.name,
                } });
            }
            try parsed_flags.addFlag(ParsedFlag.init(flag.name, FlagValue.type_boolean(true)));
            last_flag = null;
        }
    }
};

test "parse a command line having a boolean flag without explicit value" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build();
    try flags.addFlag(verbose_flag, &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "--verbose" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);
    try std.testing.expect(try parsed_flags.getBoolean("verbose"));
}

test "parse a command line having a boolean flag without explicit value followed by arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build();
    try flags.addFlag(verbose_flag, &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "--verbose", "2", "5" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);
    try std.testing.expect(try parsed_flags.getBoolean("verbose"));
}

test "parse a command line having a boolean flag with explicit value followed by arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build();
    try flags.addFlag(verbose_flag, &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "--verbose", "false", "2", "5" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);
    try std.testing.expect(try parsed_flags.getBoolean("verbose") == false);
}

test "parse a command line having a flag with explicit value followed by arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const timeout_flag = Flag.builder("timeout", "Define timeout", FlagType.int64).build();
    try flags.addFlag(timeout_flag, &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "--timeout", "50", "2", "5" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);
    try std.testing.expectEqual(50, try parsed_flags.getInt64("timeout"));
}

test "parse a command line having flags and no arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(Flag.builder("augend", "First argument to add", FlagType.int64).build(), &diagnostics);
    try flags.addFlag(Flag.builder("addend", "Second argument to add", FlagType.int64).build(), &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "--augend", "2", "--addend", "5" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual(0, parsed_arguments.items.len);
    try std.testing.expectEqual(2, try parsed_flags.getInt64("augend"));
    try std.testing.expectEqual(5, try parsed_flags.getInt64("addend"));
}

test "parse a command line having a few flags and arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder("priority", "Define priority", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder("namespace", "Define namespace", FlagType.string).withShortName('n').build(), &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "--verbose", "false", "-n", "cli-craft", "--priority" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);

    try std.testing.expect(try parsed_flags.getBoolean("verbose") == false);
    try std.testing.expect(try parsed_flags.getBoolean("priority") == true);
    try std.testing.expectEqualStrings("cli-craft", try parsed_flags.getString("namespace"));
}

test "parse a command line with flags having default value but with command line containing a different value" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder("priority", "Define priority", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(25)).withShortName('t').build(), &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "--verbose", "-t", "23", "--priority" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);

    try std.testing.expect(try parsed_flags.getBoolean("verbose") == true);
    try std.testing.expect(try parsed_flags.getBoolean("priority") == true);
    try std.testing.expectEqual(23, try parsed_flags.getInt64("timeout"));
}

test "parse a command line with flags for a command which has child commands" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(25)).withShortName('t').build(), &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--verbose", "-t", "23", "get", "pods" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, true);

    try std.testing.expectEqualStrings("get", parsed_arguments.pop().?);

    try std.testing.expect(try parsed_flags.getBoolean("verbose") == true);
    try std.testing.expectEqual(23, try parsed_flags.getInt64("timeout"));
}

test "parse a command line with flags containing explicit boolean value for a command which has child commands" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(25)).withShortName('t').build(), &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--verbose", "false", "-t", "23", "get", "pods" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(&arguments, flags, &diagnostics);
    try parser.parse(&parsed_flags, &parsed_arguments, true);

    try std.testing.expectEqualStrings("get", parsed_arguments.pop().?);

    try std.testing.expect(try parsed_flags.getBoolean("verbose") == false);
    try std.testing.expectEqual(23, try parsed_flags.getInt64("timeout"));
}
