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

/// Errors specific to command-line parsing.
pub const CommandParsingError = error{
    /// No subcommand was provided when expected.
    NoSubcommandProvided,
    /// A specified subcommand was not found or not added to its parent.
    SubcommandNotAddedToParentCommand,
    /// No flags were added to the command, but a flag was encountered during parsing.
    NoFlagsAddedToCommand,
    /// A flag was provided without a corresponding value.
    NoFlagValueProvided,
    /// A specified flag was not found in the command's flag definitions.
    FlagNotFound,
};

/// Internal state machine for the command-line parser.
const ParserState = enum {
    /// The parser is currently expecting either a flag or a positional argument.
    ExpectingFlagOrArgument,

    /// The parser has just encountered a flag that requires a value and is now expecting
    /// that value.
    ExpectingFlagValue,
};

/// A struct responsible for parsing command-line arguments and flags.
///
/// It iterates through the raw arguments, identifies flags and their values,
/// and separates them from positional arguments. It also handles basic validation
/// and reports errors via a `Diagnostics` instance.
pub const CommandLineParser = struct {
    /// A pointer to the `Arguments` iterator providing raw command-line input.
    arguments: *Arguments,
    /// The `Flags` collection containing the definitions of flags applicable to the
    /// current command.
    command_flags: Flags,
    /// A pointer to the `Diagnostics` instance for logging and reporting errors.
    diagnostics: *Diagnostics,
    /// The current state of the parser's internal state machine.
    current_state: ParserState,
    /// Stores the last `Flag` definition encountered that requires a value.
    last_received_flag: ?Flag,

    /// Initializes a new `CommandLineParser`.
    ///
    /// Parameters:
    ///   arguments: A pointer to the `Arguments` instance to parse.
    ///   command_flags: The `Flags` collection relevant to the current command context.
    ///   diagnostics: A pointer to the `Diagnostics` instance for error reporting.
    pub fn init(arguments: *Arguments, command_flags: Flags, diagnostics: *Diagnostics) CommandLineParser {
        return .{
            .arguments = arguments,
            .command_flags = command_flags,
            .diagnostics = diagnostics,
            .current_state = ParserState.ExpectingFlagOrArgument,
            .last_received_flag = null,
        };
    }

    /// Parses the command-line arguments and populates `parsed_flags` and `parsed_arguments`.
    ///
    /// This is the main parsing logic. It iterates through the arguments,
    /// identifying flags, their values, and positional arguments based on the
    /// internal state machine.
    ///
    /// Parameters:
    ///   parsed_flags: A pointer to a `ParsedFlags` instance to store the parsed flags.
    ///   parsed_arguments: A pointer to a `std.ArrayList([]const u8)` to store the parsed positional arguments.
    ///   has_subcommands: A boolean indicating if the current command expects subcommands.
    ///                    If true, parsing stops after the first positional argument (which is assumed to be the subcommand name).
    ///
    /// Returns:
    ///   `void` on successful parsing, or an error if a parsing rule is violated.
    pub fn parse(
        self: *CommandLineParser,
        parsed_flags: *ParsedFlags,
        parsed_arguments: *std.ArrayList([]const u8),
        has_subcommands: bool,
    ) !void {
        while (self.arguments.next()) |argument| {
            switch (self.current_state) {
                .ExpectingFlagOrArgument => {
                    if (Flag.looksLikeFlagName(argument)) {
                        try self.parseFlagName(argument, parsed_flags);
                    } else {
                        if (self.last_received_flag) |_| {
                            try self.parseBooleanFlagValueOrArgument(
                                argument,
                                parsed_flags,
                                parsed_arguments,
                            );
                        } else {
                            try self.addArgument(argument, parsed_arguments);
                            if (has_subcommands) {
                                break;
                            }
                        }
                    }
                },
                .ExpectingFlagValue => {
                    try self.parseFlagValue(argument, parsed_flags);
                },
            }
        }
        if (self.last_received_flag) |flag| {
            if (flag.flag_type != FlagType.boolean) {
                return self.diagnostics.reportAndFail(.{ .NoFlagValueProvided = .{
                    .parsed_flag = flag.name,
                } });
            }
            try parsed_flags.addFlag(ParsedFlag.init(flag.name, FlagValue.type_boolean(true)));
            self.last_received_flag = null;
        }
    }

    /// Internal function to parse a flag name.
    ///
    /// It normalizes the flag name (removes leading dashes), looks up the flag definition,
    /// and transitions the parser state based on whether the flag expects a value.
    ///
    /// Parameters:
    ///   argument: The raw command-line argument that looks like a flag name.
    ///   parsed_flags: A pointer to the `ParsedFlags` instance to update.
    fn parseFlagName(self: *CommandLineParser, argument: []const u8, parsed_flags: *ParsedFlags) !void {
        const flag_name = Flag.normalizeFlagName(argument);
        const last_flag: ?Flag = self.command_flags.get(flag_name) orelse return self.diagnostics.reportAndFail(.{
            .FlagNotFound = .{ .flag_name = flag_name },
        });

        const flag = last_flag.?;
        if (flag.flag_type == FlagType.boolean) {
            // For boolean flags, assume 'true' if no explicit value is given,
            // and wait if there is a boolean value.
            try parsed_flags.addFlag(ParsedFlag.init(flag.name, FlagValue.type_boolean(true)));
            self.current_state = ParserState.ExpectingFlagOrArgument;
        } else {
            // For non-boolean flags, we expect a value next.
            self.current_state = ParserState.ExpectingFlagValue;
        }
        self.last_received_flag = last_flag;
    }

    /// Internal function to parse a boolean flag's value or a positional argument.
    ///
    /// This is called when `last_received_flag` is set (meaning a value-expecting flag was just seen).
    /// It checks if the current `argument` is a valid boolean value for the flag.
    /// If not, it treats the `argument` as a positional argument.
    ///
    /// Parameters:
    ///   argument: The current raw command-line argument.
    ///   parsed_flags: A pointer to the `ParsedFlags` instance to update.
    ///   parsed_arguments: A pointer to the `std.ArrayList([]const u8)` to add positional arguments to.
    fn parseBooleanFlagValueOrArgument(
        self: *CommandLineParser,
        argument: []const u8,
        parsed_flags: *ParsedFlags,
        parsed_arguments: *std.ArrayList([]const u8),
    ) !void {
        if (Flag.looksLikeBooleanFlagValue(argument)) {
            const flag = self.last_received_flag.?;
            const flag_value = try flag.toFlagValue(argument, self.diagnostics);
            try parsed_flags.updateFlag(ParsedFlag.init(flag.name, flag_value));
        } else {
            // If it's not a boolean flag, or the argument isn't a boolean value,
            // then this argument is a positional argument.
            try self.addArgument(argument, parsed_arguments);
        }
        self.current_state = ParserState.ExpectingFlagOrArgument;
        self.last_received_flag = null;
    }

    /// Internal function to add a positional argument to the `parsed_arguments` list.
    ///
    /// Parameters:
    ///   argument: The positional argument to add.
    ///   parsed_arguments: A pointer to the `std.ArrayList([]const u8)` to add the argument to.
    fn addArgument(self: *CommandLineParser, argument: []const u8, parsed_arguments: *std.ArrayList([]const u8)) !void {
        try parsed_arguments.append(argument);
        self.current_state = ParserState.ExpectingFlagOrArgument;
        self.last_received_flag = null;
    }

    /// Internal function to parse the value for a non-boolean flag.
    ///
    /// This is called when `current_state` is `ExpectingFlagValue`. It validates
    /// that the argument is not another flag name and converts it to the expected
    /// `FlagValue` type.
    ///
    /// Parameters:
    ///   argument: The raw command-line argument expected to be the flag's value.
    ///   parsed_flags: A pointer to the `ParsedFlags` instance to update.
    fn parseFlagValue(self: *CommandLineParser, argument: []const u8, parsed_flags: *ParsedFlags) !void {
        // If we're expecting a flag value and we see something that looks like a flag name,
        // it means the previous flag was provided without a value.
        if (Flag.looksLikeFlagName(argument)) {
            return self.diagnostics.reportAndFail(.{ .NoFlagValueProvided = .{
                .parsed_flag = self.last_received_flag.?.name,
            } });
        }
        const flag = self.last_received_flag.?;
        const flag_value = try flag.toFlagValue(argument, self.diagnostics);

        try parsed_flags.addFlag(ParsedFlag.init(flag.name, flag_value));

        self.last_received_flag = null;
        self.current_state = ParserState.ExpectingFlagOrArgument;
    }
};

const FlagErrors = @import("flags.zig").FlagErrors;
const FlagFactory = @import("flags.zig").FlagFactory;

test "attempt to parse a command line without explicit value for a non-boolean flag" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const priority_flag = try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Define priority",
        FlagType.int64,
    ).build();

    try flags.addFlag(priority_flag, &diagnostics);
    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "--priority" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try std.testing.expectError(
        CommandParsingError.NoFlagValueProvided,
        parser.parse(
            &parsed_flags,
            &parsed_arguments,
            false,
        ),
    );

    const diagnostics_type = diagnostics.diagnostics_type.?.NoFlagValueProvided;
    try std.testing.expectEqualStrings("priority", diagnostics_type.parsed_flag);
}

test "attempt to parse a command line with an unregistered flag" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const priority_flag = try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Define priority",
        FlagType.int64,
    ).build();

    try flags.addFlag(priority_flag, &diagnostics);
    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "--namespace", "cli-craft" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try std.testing.expectError(
        CommandParsingError.FlagNotFound,
        parser.parse(
            &parsed_flags,
            &parsed_arguments,
            false,
        ),
    );

    const diagnostics_type = diagnostics.diagnostics_type.?.FlagNotFound;
    try std.testing.expectEqualStrings("namespace", diagnostics_type.flag_name);
}

test "attempt to parse a command line with an invalid integer value" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const priority_flag = try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Define priority",
        FlagType.int64,
    ).build();

    try flags.addFlag(priority_flag, &diagnostics);
    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "--priority", "cli-craft" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try std.testing.expectError(
        FlagErrors.InvalidInteger,
        parser.parse(
            &parsed_flags,
            &parsed_arguments,
            false,
        ),
    );

    const diagnostics_type = diagnostics.diagnostics_type.?.InvalidInteger;
    try std.testing.expectEqualStrings("priority", diagnostics_type.flag_name);
    try std.testing.expectEqualStrings("cli-craft", diagnostics_type.value);
}

test "parse a command line having a boolean flag without explicit value" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build();
    try flags.addFlag(verbose_flag, &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "--verbose" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);
    try std.testing.expect(try parsed_flags.getBoolean("verbose"));
}

test "parse a command line having a boolean flag without explicit value followed by arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build();
    try flags.addFlag(verbose_flag, &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "--verbose", "2", "5" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);
    try std.testing.expect(try parsed_flags.getBoolean("verbose"));
}

test "parse a command line having a boolean flag with explicit value followed by arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build();
    try flags.addFlag(verbose_flag, &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "--verbose", "false", "2", "5" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);
    try std.testing.expect(try parsed_flags.getBoolean("verbose") == false);
}

test "parse a command line having a flag with explicit value followed by arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    const timeout_flag = try FlagFactory.init(std.testing.allocator).builder(
        "timeout",
        "Define timeout",
        FlagType.int64,
    ).build();
    try flags.addFlag(timeout_flag, &diagnostics);

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "--timeout", "50", "2", "5" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);
    try std.testing.expectEqual(50, try parsed_flags.getInt64("timeout"));
}

test "parse a command line having flags and no arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "augend",
            "First argument to add",
            FlagType.int64,
        ).build(),
        &diagnostics,
    );
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "addend",
            "Second argument to add",
            FlagType.int64,
        ).build(),
        &diagnostics,
    );

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "--augend", "2", "--addend", "5" });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(&parsed_flags, &parsed_arguments, false);

    try std.testing.expectEqual(0, parsed_arguments.items.len);
    try std.testing.expectEqual(2, try parsed_flags.getInt64("augend"));
    try std.testing.expectEqual(5, try parsed_flags.getInt64("addend"));
}

test "parse a command line having a few flags and arguments" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "verbose",
            "Enable verbose output",
            FlagType.boolean,
        ).build(),
        &diagnostics,
    );
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "priority",
            "Define priority",
            FlagType.boolean,
        ).build(),
        &diagnostics,
    );
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "namespace",
            "Define namespace",
            FlagType.string,
        ).withShortName('n').build(),
        &diagnostics,
    );

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{
        "add",
        "2",
        "5",
        "--verbose",
        "false",
        "-n",
        "cli-craft",
        "--priority",
    });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(
        &parsed_flags,
        &parsed_arguments,
        false,
    );

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);

    try std.testing.expect(try parsed_flags.getBoolean("verbose") == false);
    try std.testing.expect(try parsed_flags.getBoolean("priority") == true);
    try std.testing.expectEqualStrings("cli-craft", try parsed_flags.getString("namespace"));
}

test "parse a command line with flags having default value but with command line containing a different value" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "verbose",
            "Enable verbose output",
            FlagType.boolean,
        ).build(),
        &diagnostics,
    );
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "priority",
            "Define priority",
            FlagType.boolean,
        ).build(),
        &diagnostics,
    );
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
            "timeout",
            "Define timeout",
            FlagValue.type_int64(25),
        ).withShortName('t').build(),
        &diagnostics,
    );

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{
        "add",
        "2",
        "5",
        "--verbose",
        "-t",
        "23",
        "--priority",
    });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(
        &parsed_flags,
        &parsed_arguments,
        false,
    );

    try std.testing.expectEqual("5", parsed_arguments.pop().?);
    try std.testing.expectEqual("2", parsed_arguments.pop().?);

    try std.testing.expect(try parsed_flags.getBoolean("verbose") == true);
    try std.testing.expect(try parsed_flags.getBoolean("priority") == true);
    try std.testing.expectEqual(23, try parsed_flags.getInt64("timeout"));
}

test "parse a command line with flags for a command which has child commands" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "verbose",
            "Enable verbose output",
            FlagType.boolean,
        ).build(),
        &diagnostics,
    );
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
            "timeout",
            "Define timeout",
            FlagValue.type_int64(25),
        ).withShortName('t').build(),
        &diagnostics,
    );

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{
        "kubectl",
        "--verbose",
        "-t",
        "23",
        "get",
        "pods",
    });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(&parsed_flags, &parsed_arguments, true);

    try std.testing.expectEqualStrings("get", parsed_arguments.pop().?);

    try std.testing.expect(try parsed_flags.getBoolean("verbose") == true);
    try std.testing.expectEqual(23, try parsed_flags.getInt64("timeout"));
}

test "parse a command line with flags containing explicit boolean value for a command which has child commands" {
    var flags = Flags.init(std.testing.allocator);

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builder(
            "verbose",
            "Enable verbose output",
            FlagType.boolean,
        ).build(),
        &diagnostics,
    );
    try flags.addFlag(
        try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
            "timeout",
            "Define timeout",
            FlagValue.type_int64(25),
        ).withShortName('t').build(),
        &diagnostics,
    );

    defer flags.deinit();

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    var parsed_arguments = std.ArrayList([]const u8).init(std.testing.allocator);
    defer parsed_arguments.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{
        "kubectl",
        "--verbose",
        "false",
        "-t",
        "23",
        "get",
        "pods",
    });
    arguments.skipFirst();

    var parser = CommandLineParser.init(
        &arguments,
        flags,
        &diagnostics,
    );
    try parser.parse(&parsed_flags, &parsed_arguments, true);

    try std.testing.expectEqualStrings("get", parsed_arguments.pop().?);

    try std.testing.expect(try parsed_flags.getBoolean("verbose") == false);
    try std.testing.expectEqual(23, try parsed_flags.getInt64("timeout"));
}
