const CommandAction = @import("command-action.zig").CommandAction;
const ArgumentSpecification = @import("argument-specification.zig").ArgumentSpecification;
const Arguments = @import("arguments.zig").Arguments;
const Flags = @import("flags.zig").Flags;
const Flag = @import("flags.zig").Flag;
const FlagType = @import("flags.zig").FlagType;
const FlagValue = @import("flags.zig").FlagValue;

const ParsedFlags = @import("flags.zig").ParsedFlags;
const ParsedFlag = @import("flags.zig").ParsedFlag;

const CommandLineParser = @import("command-line-parser.zig").CommandLineParser;
const CommandParsingError = @import("command-line-parser.zig").CommandParsingError;

pub const CommandFnArguments = [][]const u8;
pub const CommandFn = *const fn (flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void;
pub const CommandAlias = []const u8;
pub const CommandAliases = []const CommandAlias;

pub const Command = struct {
    name: []const u8,
    description: []const u8,
    allocator: std.mem.Allocator,
    action: CommandAction,
    aliases: ?CommandAliases = null,
    argument_specification: ?ArgumentSpecification = null,
    deprecated_message: ?[]const u8 = null,
    has_parent: bool = false,
    flags: ?Flags = null,

    pub fn init(name: []const u8, description: []const u8, executable: CommandFn, allocator: std.mem.Allocator) Command {
        return .{
            .name = name,
            .description = description,
            .allocator = allocator,
            .action = CommandAction.initExecutable(executable),
        };
    }

    pub fn initParent(name: []const u8, description: []const u8, allocator: std.mem.Allocator) !Command {
        return .{
            .name = name,
            .description = description,
            .allocator = allocator,
            .action = try CommandAction.initSubcommands(allocator),
        };
    }

    pub fn addAliases(self: *Command, aliases: CommandAliases) void {
        self.aliases = aliases;
    }

    pub fn addSubcommand(self: *Command, subcommand: *Command) !void {
        subcommand.has_parent = true;
        try self.action.addSubcommand(subcommand.*);
    }

    pub fn setArgumentSpecification(self: *Command, specification: ArgumentSpecification) void {
        self.argument_specification = specification;
    }

    pub fn addLocalFlag(self: *Command, flag: Flag) !void {
        if (self.flags == null) {
            self.flags = Flags.init(self.allocator);
        }
        try self.flags.?.addFlag(flag);
    }

    pub fn markDeprecated(self: *Command, deprecated_message: []const u8) void {
        self.deprecated_message = deprecated_message;
    }

    //TODO: print deprecated message if the command is deprecated
    pub fn execute(self: Command, arguments: *Arguments, allocator: std.mem.Allocator) !void {
        switch (self.action) {
            .executable => |executable_fn| {
                var parsed_flags = ParsedFlags.init(allocator);
                defer parsed_flags.deinit();

                var parsed_arguments = std.ArrayList([]const u8).init(allocator);
                defer parsed_arguments.deinit();

                var command_line_parser = CommandLineParser.init(arguments, self.flags);
                try command_line_parser.parse(&parsed_flags, &parsed_arguments);

                if (self.argument_specification) |argument_specification| {
                    try argument_specification.validate(parsed_arguments.items.len);
                }
                return executable_fn(parsed_flags, parsed_arguments.items);
            },
            .subcommands => |sub_commands| {
                const subcommand_name = arguments.next() orelse return CommandParsingError.NoSubcommandProvided;
                const command = sub_commands.get(subcommand_name) orelse return CommandParsingError.SubcommandNotAddedToParentCommand;

                return command.execute(arguments, allocator);
            },
        }
    }

    pub fn deinit(self: *Command) void {
        self.action.deinit();
        if (self.flags) |*flags| {
            flags.deinit();
        }
    }
};

const std = @import("std");

test "initialize a command with an executable action" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("test", "test command", runnable, std.testing.allocator);
    defer command.deinit();

    try std.testing.expectEqualStrings("test", command.name);
    try std.testing.expectEqualStrings("test command", command.description);
}

test "initialize a command with an executable action and mark it as deprecated" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("test", "test command", runnable, std.testing.allocator);
    command.markDeprecated("This command is deprecated");
    defer command.deinit();

    try std.testing.expectEqualStrings("This command is deprecated", command.deprecated_message.?);
}

test "initialize a command with a local flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build();

    var command = Command.init("test", "test command", runnable, std.testing.allocator);
    try command.addLocalFlag(verbose_flag);

    defer command.deinit();

    try std.testing.expect(command.flags != null);
    try std.testing.expectEqualStrings("verbose", command.flags.?.get("verbose").?.name);
}

test "initialize a command without any flags" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("test", "test command", runnable, std.testing.allocator);
    defer command.deinit();

    try std.testing.expect(command.flags == null);
}

test "initialize an executable command with an alias" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    command.addAliases(&[_]CommandAlias{"str"});

    defer command.deinit();

    try std.testing.expect(command.aliases != null);

    const aliases: CommandAliases = command.aliases.?;

    try std.testing.expectEqual(aliases.len, 1);
    try std.testing.expectEqualStrings("str", aliases[0]);
}

test "initialize an executable command with a couple of aliases" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    command.addAliases(&[_]CommandAlias{ "str", "strm" });

    defer command.deinit();

    try std.testing.expect(command.aliases != null);

    const aliases: CommandAliases = command.aliases.?;

    try std.testing.expectEqual(aliases.len, 2);
    try std.testing.expectEqualStrings("str", aliases[0]);
    try std.testing.expectEqualStrings("strm", aliases[1]);
}

test "initialize a parent command with subcommands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable, std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(kubectl_command.action.subcommands.get("get") != null);
    try std.testing.expectEqualStrings("get", kubectl_command.action.subcommands.get("get").?.name);
}

test "initialize an executable command with argument specification (1)" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    command.setArgumentSpecification(ArgumentSpecification.mustBeMinimum(1));

    defer command.deinit();

    try std.testing.expect(command.argument_specification != null);
    try std.testing.expectEqual(ArgumentSpecification.mustBeMinimum(1), command.argument_specification.?);
}

test "initialize an executable command with argument specification (2)" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    command.setArgumentSpecification(ArgumentSpecification.mustBeInEndInclusiveRange(1, 5));

    defer command.deinit();

    try std.testing.expect(command.argument_specification != null);
    try std.testing.expectEqual(ArgumentSpecification.mustBeInEndInclusiveRange(1, 5), command.argument_specification.?);
}

var add_command_result: u8 = undefined;
var get_command_result: []const u8 = undefined;
var add_command_result_via_flags: i64 = undefined;

test "execute a command with an executable command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            add_command_result = augend + addend;
            return;
        }
    }.run;

    var command = Command.init("add", "add numbers", runnable, std.testing.allocator);
    defer command.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5" });
    arguments.skipFirst();

    try command.execute(&arguments, std.testing.allocator);
    try std.testing.expectEqual(7, add_command_result);
}

test "execute a command with a subcommand" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            get_command_result = arguments[0];
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable, std.testing.allocator);
    defer get_command.deinit();

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods" });
    arguments.skipFirst();

    try kubectl_command.execute(&arguments, std.testing.allocator);
    try std.testing.expectEqualStrings("pods", get_command_result);
}

test "attempt to execute a command with a subcommand but with incorrect command name from the argument" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable, std.testing.allocator);
    defer get_command.deinit();

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "delete" });
    arguments.skipFirst();

    try std.testing.expectError(CommandParsingError.SubcommandNotAddedToParentCommand, kubectl_command.execute(&arguments, std.testing.allocator));
}

test "execute a command with flags and arguments" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            try std.testing.expect(try flags.getBoolean("verbose"));
            try std.testing.expect(try flags.getBoolean("priority"));
            try std.testing.expectEqual(23, try flags.getInt64("timeout"));

            add_command_result = augend + addend;
            return;
        }
    }.run;

    var command = Command.init("add", "add numbers", runnable, std.testing.allocator);
    try command.addLocalFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build());
    try command.addLocalFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).build());
    try command.addLocalFlag(Flag.builder("timeout", "Define timeout", FlagType.int64).withShortName('t').withDefaultValue(FlagValue.type_int64(10)).build());
    defer command.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "-t", "23", "2", "5", "--verbose", "--priority" });
    arguments.skipFirst();

    try command.execute(&arguments, std.testing.allocator);
    try std.testing.expectEqual(7, add_command_result);
}
