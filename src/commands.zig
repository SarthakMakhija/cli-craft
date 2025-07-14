const std = @import("std");

const CommandAction = @import("command-action.zig").CommandAction;
const Arguments = @import("arguments.zig").Arguments;
const Flags = @import("flags.zig").Flags;
const Flag = @import("flags.zig").Flag;
const FlagType = @import("flags.zig").FlagType;
const FlagValue = @import("flags.zig").FlagValue;
const FlagErrors = @import("flags.zig").FlagErrors;
const Diagnostics = @import("diagnostics.zig").Diagnostics;

const ParsedFlags = @import("flags.zig").ParsedFlags;
const ParsedFlag = @import("flags.zig").ParsedFlag;

const CommandLineParser = @import("command-line-parser.zig").CommandLineParser;
const CommandParsingError = @import("command-line-parser.zig").CommandParsingError;

const CommandsHelp = @import("help.zig").CommandsHelp;
const OutputStream = @import("stream.zig").OutputStream;

const prettytable = @import("prettytable");

pub const HelpCommandName = "help";

pub const CommandAddError = error{ ChildCommandAdded, CommandNameAlreadyExists, CommandAliasAlreadyExists, SubCommandAddedToExecutable, SubCommandNameSameAsParent };

pub const CommandExecutionError = error{
    MissingCommandNameToExecute,
    CommandNotFound,
};

pub const CommandErrors = CommandAddError || CommandExecutionError || CommandParsingError;

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
    local_flags: ?Flags = null,
    persistent_flags: ?Flags = null,
    output_stream: OutputStream,

    pub fn init(name: []const u8, description: []const u8, executable: CommandFn, output_stream: OutputStream, allocator: std.mem.Allocator) Command {
        var local_flags = Flags.init(allocator);
        local_flags.addHelp() catch {};

        return .{
            .name = name,
            .description = description,
            .allocator = allocator,
            .action = CommandAction.initExecutable(executable),
            .output_stream = output_stream,
            .local_flags = local_flags,
        };
    }

    pub fn initParent(name: []const u8, description: []const u8, output_stream: OutputStream, allocator: std.mem.Allocator) !Command {
        var local_flags = Flags.init(allocator);
        local_flags.addHelp() catch {};

        return .{
            .name = name,
            .description = description,
            .allocator = allocator,
            .action = try CommandAction.initSubcommands(allocator, output_stream),
            .output_stream = output_stream,
            .local_flags = local_flags,
        };
    }

    pub fn addAliases(self: *Command, aliases: CommandAliases) void {
        self.aliases = aliases;
    }

    pub fn addSubcommand(self: *Command, subcommand: *Command) !void {
        var diagnostics: Diagnostics = .{};
        self.action.addSubcommand(self.name, subcommand, &diagnostics) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    pub fn setArgumentSpecification(self: *Command, specification: ArgumentSpecification) void {
        self.argument_specification = specification;
    }

    pub fn addFlag(self: *Command, flag: Flag) !void {
        var diagnostics: Diagnostics = .{};
        var target_flags: *?Flags = undefined;

        if (flag.persistent) {
            try self.ensureLocalFlagsDoNotContain(flag);
            self.persistent_flags = self.persistent_flags orelse Flags.init(self.allocator);
            target_flags = &self.persistent_flags;
        } else {
            try self.ensurePersistentFlagsDoNotContain(flag);
            self.local_flags = self.local_flags orelse Flags.init(self.allocator);
            target_flags = &self.local_flags;
        }
        target_flags.*.?.addFlag(flag, &diagnostics) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    pub fn markDeprecated(self: *Command, deprecated_message: []const u8) void {
        self.deprecated_message = deprecated_message;
    }

    pub fn printAliases(self: Command, table: *prettytable.Table) !void {
        if (self.aliases) |aliases| {
            if (aliases.len > 0) {
                try self.output_stream.print("Aliases:\n", .{});
                for (aliases) |alias| {
                    try table.addRow(&[_][]const u8{alias});
                }
            }
        }
        try self.output_stream.printTable(table);
    }

    pub fn deinit(self: *Command) void {
        self.action.deinit();
        if (self.local_flags) |*flags| {
            flags.deinit();
        }
        if (self.persistent_flags) |*flags| {
            flags.deinit();
        }
    }

    fn ensureLocalFlagsDoNotContain(self: Command, flag: Flag) !void {
        var diagnostics: Diagnostics = .{};
        if (self.local_flags) |local_flags| {
            local_flags.ensureFlagDoesNotExist(flag, &diagnostics) catch |err| {
                diagnostics.log_using(self.output_stream);
                return err;
            };
        }
    }

    fn ensurePersistentFlagsDoNotContain(self: Command, flag: Flag) !void {
        var diagnostics: Diagnostics = .{};
        if (self.persistent_flags) |persistent_flags| {
            persistent_flags.ensureFlagDoesNotExist(flag, &diagnostics) catch |err| {
                diagnostics.log_using(self.output_stream);
                return err;
            };
        }
    }

    fn isHelp(self: Command) bool {
        return std.mem.eql(u8, self.name, HelpCommandName);
    }

    //TODO: print deprecated message if the command is deprecated
    fn execute(self: Command, arguments: *Arguments, diagnostics: *Diagnostics, allocator: std.mem.Allocator) !void {
        var flags = Flags.init(allocator);
        defer flags.deinit();

        var parsed_flags = ParsedFlags.init(allocator);
        defer parsed_flags.deinit();

        return try self.executeInternal(arguments, &flags, &parsed_flags, diagnostics, allocator);
    }

    fn executeInternal(self: Command, arguments: *Arguments, inherited_flags: *Flags, inherited_parsed_flags: *ParsedFlags, diagnostics: *Diagnostics, allocator: std.mem.Allocator) !void {
        var all_flags = Flags.init(allocator);
        defer all_flags.deinit();

        try self.merge_flags(inherited_flags, &all_flags, true, diagnostics);

        var parsed_flags = ParsedFlags.init(allocator);
        defer parsed_flags.deinit();

        try parsed_flags.merge(inherited_parsed_flags);

        var parsed_arguments = std.ArrayList([]const u8).init(allocator);
        defer parsed_arguments.deinit();

        var command_line_parser = CommandLineParser.init(arguments, all_flags, diagnostics);
        try command_line_parser.parse(&parsed_flags, &parsed_arguments, if (self.action == .executable) false else true);

        switch (self.action) {
            .executable => |executable_fn| {
                if (self.argument_specification) |argument_specification| {
                    try argument_specification.validate(parsed_arguments.items.len);
                }

                try all_flags.addFlagsWithDefaultValueTo(&parsed_flags);
                return executable_fn(parsed_flags, parsed_arguments.items);
            },
            .subcommands => |sub_commands| {
                const sub_command = try self.get_subcommand(&parsed_arguments, sub_commands, diagnostics);

                var child_flags = Flags.init(allocator);
                defer child_flags.deinit();

                try self.merge_flags(inherited_flags, &child_flags, false, diagnostics);
                try child_flags.addFlagsWithDefaultValueTo(&parsed_flags);

                return sub_command.executeInternal(arguments, &child_flags, &parsed_flags, diagnostics, allocator);
            },
        }
    }

    fn merge_flags(self: Command, inherited_flags: *Flags, target_flags: *Flags, should_merge_local_flags: bool, diagnostics: *Diagnostics) !void {
        if (should_merge_local_flags) {
            if (self.local_flags) |local_flags| {
                try target_flags.merge(&local_flags, diagnostics);
            }
        }
        if (self.persistent_flags) |persistent_flags| {
            try target_flags.merge(&persistent_flags, diagnostics);
        }
        try target_flags.merge(inherited_flags, diagnostics);
    }

    fn get_subcommand(self: Command, parsed_arguments: *std.ArrayList([]const u8), sub_commands: Commands, diagnostics: *Diagnostics) !Command {
        if (parsed_arguments.items.len == 0) {
            return diagnostics.reportAndFail(.{ .NoSubcommandProvided = .{
                .command = self.name,
            } });
        }
        const subcommand_name = parsed_arguments.pop() orelse
            return diagnostics.reportAndFail(.{ .NoSubcommandProvided = .{
                .command = self.name,
            } });

        const sub_command = sub_commands.get(subcommand_name) orelse
            return diagnostics.reportAndFail(.{ .SubcommandNotAddedToParentCommand = .{
                .command = self.name,
                .subcommand = subcommand_name,
            } });
        return sub_command;
    }
};

pub const Commands = struct {
    command_by_name: std.StringHashMap(Command),
    command_name_by_alias: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    output_stream: OutputStream,

    pub fn init(
        allocator: std.mem.Allocator,
        output_stream: OutputStream,
    ) Commands {
        return .{
            .command_by_name = std.StringHashMap(Command).init(allocator),
            .command_name_by_alias = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
            .output_stream = output_stream,
        };
    }

    pub fn addHelp(self: *Commands) !void {
        const runnable = struct {
            pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
                return;
            }
        }.run;

        const command = Command.init("help", "Displays system help", runnable, self.output_stream, self.allocator);
        try self.command_by_name.put("help", command);
    }

    pub fn add_allow_child(self: *Commands, command: Command, diagnostics: *Diagnostics) !void {
        return try self.add(command, true, diagnostics);
    }

    pub fn add_disallow_child(self: *Commands, command: Command, diagnostics: *Diagnostics) !void {
        return try self.add(command, false, diagnostics);
    }

    pub fn get(self: Commands, command_name_or_alias: []const u8) ?Command {
        if (self.command_by_name.get(command_name_or_alias)) |command| {
            return command;
        }
        if (self.command_name_by_alias.get(command_name_or_alias)) |command_name| {
            return self.command_by_name.get(command_name);
        }
        return null;
    }

    pub fn execute(self: Commands, arguments: *Arguments, diagnostics: *Diagnostics) !void {
        const command_name_or_alias = arguments.next() orelse return diagnostics.reportAndFail(.{ .MissingCommandNameToExecute = .{} });
        const command = self.get(command_name_or_alias) orelse return diagnostics.reportAndFail(.{ .CommandNotFound = .{ .command = command_name_or_alias } });

        //TODO: pass app description.
        if (command.isHelp()) {
            const help = CommandsHelp.init(self, null, self.output_stream);
            try help.printHelp(self.allocator);
        }
        return try command.execute(arguments, diagnostics, self.allocator);
    }

    pub fn deinit(self: *Commands) void {
        var iterator = self.command_by_name.valueIterator();
        while (iterator.next()) |command| {
            command.deinit();
        }
        self.command_name_by_alias.deinit();
        self.command_by_name.deinit();
    }

    pub fn print(self: Commands, table: *prettytable.Table, allocator: std.mem.Allocator) !void {
        var column_values = std.ArrayList([]const u8).init(allocator);
        defer {
            for (column_values.items) |column_value| {
                allocator.free(column_value);
            }
            column_values.deinit();
        }

        try self.output_stream.print("Available Commands:\n", .{});
        var iterator = self.command_by_name.iterator();

        var aliases_str: []const u8 = "";
        while (iterator.next()) |entry| {
            const command_name = entry.key_ptr.*;
            const command = entry.value_ptr;

            aliases_str = "";
            if (command.aliases) |aliases| {
                if (aliases.len > 0) {
                    var aliases_builder = std.ArrayList(u8).init(allocator);
                    defer aliases_builder.deinit();

                    var first_alias = true;
                    try aliases_builder.writer().writeAll("(");

                    for (aliases) |alias| {
                        if (!first_alias) {
                            try aliases_builder.writer().writeAll(", ");
                        }
                        try aliases_builder.writer().print("{s}", .{alias});
                        first_alias = false;
                    }
                    try aliases_builder.writer().writeAll(")");
                    aliases_str = try aliases_builder.toOwnedSlice();

                    try column_values.append(aliases_str);
                }
            }
            try table.addRow(&[_][]const u8{ command_name, aliases_str, command.description });
        }

        try self.output_stream.printTable(table);
    }

    fn add(self: *Commands, command: Command, allow_child: bool, diagnostics: *Diagnostics) !void {
        if (!allow_child and command.has_parent) {
            return diagnostics.reportAndFail(.{ .ChildCommandAdded = .{ .command = command.name } });
        }

        try self.ensureCommandDoesNotExist(command, diagnostics);
        try self.command_by_name.put(command.name, command);

        if (command.aliases) |aliases| {
            for (aliases) |alias| {
                try self.command_name_by_alias.put(alias, command.name);
            }
        }
    }

    fn ensureCommandDoesNotExist(self: Commands, command: Command, diagnostics: *Diagnostics) !void {
        if (self.command_by_name.contains(command.name)) {
            return diagnostics.reportAndFail(.{ .CommandNameAlreadyExists = .{ .command = command.name } });
        }
        if (command.aliases) |aliases| {
            for (aliases) |alias| {
                if (self.command_name_by_alias.get(alias)) |other_command_name| {
                    return diagnostics.reportAndFail(.{ .CommandAliasAlreadyExists = .{
                        .alias = alias,
                        .existing_command = other_command_name,
                    } });
                }
            }
        }
        return;
    }
};

test "initialize a command with an executable action" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("test", "test command", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
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

    var command = Command.init("test", "test command", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
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

    var command = Command.init("test", "test command", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(verbose_flag);

    defer command.deinit();

    try std.testing.expect(command.local_flags != null);
    try std.testing.expectEqualStrings("verbose", command.local_flags.?.get("verbose").?.name);
}

test "initialize a command without any flags" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("test", "test command", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try std.testing.expect(command.local_flags.?.get("help") != null);
}

test "initialize an executable command with an alias" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
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

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
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

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
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

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
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

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    command.setArgumentSpecification(try ArgumentSpecification.mustBeInEndInclusiveRange(1, 5));

    defer command.deinit();

    try std.testing.expect(command.argument_specification != null);
    try std.testing.expectEqual(ArgumentSpecification.mustBeInEndInclusiveRange(1, 5), command.argument_specification.?);
}

test "is help command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("help", "prints help", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try std.testing.expect(command.isHelp());
}

test "is not a help command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("HELP", "prints help", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try std.testing.expect(command.isHelp() == false);
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

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try command.execute(&arguments, &diagnostics, std.testing.allocator);

    try std.testing.expectEqual(7, add_command_result);
}

test "execute a command with a subcommand" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            get_command_result = arguments[0];
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);

    try std.testing.expectEqualStrings("pods", get_command_result);
}

test "attempt to execute a command with a subcommand but with incorrect subcommand name from the argument" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "delete" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(CommandParsingError.SubcommandNotAddedToParentCommand, kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator));
}

test "add a local flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).build());
    defer command.deinit();

    try std.testing.expectEqualStrings("priority", command.local_flags.?.get("priority").?.name);
}

test "attempt to add an existing local flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).build());
    defer command.deinit();

    try std.testing.expectError(FlagErrors.FlagNameAlreadyExists, command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).build()));
}

test "attempt to add a local flag which exists as persistent flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).markPersistent().build());
    try std.testing.expectError(FlagErrors.FlagNameAlreadyExists, command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).build()));
}

test "add a persistent flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).markPersistent().build());
    defer command.deinit();

    try std.testing.expectEqualStrings("priority", command.persistent_flags.?.get("priority").?.name);
}

test "attempt to add an existing persistent flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).markPersistent().build());

    defer command.deinit();

    try std.testing.expectError(FlagErrors.FlagNameAlreadyExists, command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).markPersistent().build()));
}

test "attempt to add a persistent flag which exists as local flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).build());

    defer command.deinit();

    try std.testing.expectError(FlagErrors.FlagNameAlreadyExists, command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).markPersistent().build()));
}

test "print command aliases" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initStdErrWriter(writer.any()), std.testing.allocator);
    command.addAliases(&[_]CommandAlias{ "str", "strm" });

    defer command.deinit();

    try std.testing.expect(command.aliases != null);

    var table = prettytable.Table.init(std.testing.allocator);
    defer table.deinit();

    table.setFormat(prettytable.FORMAT_CLEAN);
    try command.printAliases(&table);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "str").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "strm").? > 0);
}

test "execute a command passing flags and arguments" {
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

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build());
    try command.addFlag(Flag.builder("priority", "Enable priority", FlagType.boolean).build());
    try command.addFlag(Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(25)).withShortName('t').build());
    defer command.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "-t", "23", "2", "5", "--verbose", "--priority" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try command.execute(&arguments, &diagnostics, std.testing.allocator);
    try std.testing.expectEqual(7, add_command_result);
}

test "execute a command with child command passing flags and arguments 1" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose"));

            return;
        }
    }.run;

    var get_command = Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(Flag.builder("namespace", "Define namespace", FlagType.string).markPersistent().build());
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "--verbose", "pods" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments 2" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);

            return;
        }
    }.run;

    var get_command = Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(Flag.builder("namespace", "Define namespace", FlagType.string).markPersistent().build());
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments with a persistent flag having default value" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);
            try std.testing.expectEqual(100, try flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(Flag.builder("namespace", "Define namespace", FlagType.string).markPersistent().build());
    try kubectl_command.addFlag(Flag.builder_with_default_value("priority", "Define priority", FlagValue.type_int64(100)).markPersistent().build());
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments with a local flag having default value 1" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);
            try std.testing.expectError(FlagErrors.FlagNotFound, flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(Flag.builder("namespace", "Define namespace", FlagType.string).markPersistent().build());
    try kubectl_command.addFlag(Flag.builder_with_default_value("priority", "Define priority", FlagValue.type_int64(100)).build());
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments with a local flag having default value 2" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);
            try std.testing.expectEqual(20, try flags.getInt64("timeout"));
            try std.testing.expectError(FlagErrors.FlagNotFound, flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(Flag.builder("namespace", "Define namespace", FlagType.string).markPersistent().build());
    try kubectl_command.addFlag(Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(20)).markPersistent().build());
    try kubectl_command.addFlag(Flag.builder_with_default_value("priority", "Define priority", FlagValue.type_int64(100)).build());
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments with a local flag having default value 3" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);
            try std.testing.expectEqual(40, try flags.getInt64("timeout"));
            try std.testing.expectError(FlagErrors.FlagNotFound, flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(Flag.builder("verbose", "Enable verbose output", FlagType.boolean).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(Flag.builder("namespace", "Define namespace", FlagType.string).markPersistent().build());
    try kubectl_command.addFlag(Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(20)).markPersistent().build());
    try kubectl_command.addFlag(Flag.builder_with_default_value("priority", "Define priority", FlagValue.type_int64(100)).build());
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "--timeout", "40", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

const ArgumentSpecification = @import("argument-specification.zig").ArgumentSpecification;
const ArgumentSpecificationError = @import("argument-specification.zig").ArgumentValidationError;

test "attempt to add a command which has a parent" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(CommandAddError.ChildCommandAdded, commands.add_disallow_child(get_command, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.ChildCommandAdded;
    try std.testing.expectEqualStrings("get", diagnostics_type.command);
}

test "add a command which has a child" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var get_command = Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(kubectl_command, &diagnostics);

    const retrieved = commands.get("kubectl");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("kubectl", retrieved.?.name);
}

test "add a command with a name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    const command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(command, &diagnostics);

    const retrieved = commands.get("stringer");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("stringer", retrieved.?.name);
}

test "add a command with a name and an alias" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    command.addAliases(&[_]CommandAlias{"str"});

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(command, &diagnostics);

    const retrieved = commands.get("str");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("stringer", retrieved.?.name);
}

test "add a command with a name and a couple of aliases" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(command, &diagnostics);

    try std.testing.expectEqualStrings("stringer", commands.get("str").?.name);
    try std.testing.expectEqualStrings("stringer", commands.get("strm").?.name);
}

test "print commands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var add_command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    add_command.addAliases(&[_]CommandAlias{"sum"});

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();

    var commands = Commands.init(std.testing.allocator, OutputStream.initStdErrWriter(writer.any()));
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(command, &diagnostics);
    try commands.add_disallow_child(add_command, &diagnostics);

    var table = prettytable.Table.init(std.testing.allocator);
    defer table.deinit();

    table.setFormat(prettytable.FORMAT_CLEAN);

    try commands.print(&table, std.testing.allocator);
    const value = buffer.items;

    try std.testing.expect(std.mem.indexOf(u8, value, "stringer").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "str").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "strm").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "sum").? > 0);
}

test "attempt to add a command with an existing name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    const command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    var diagnostics: Diagnostics = .{};

    try commands.add_disallow_child(command, &diagnostics);

    var another_command = Command.init("stringer", "manipulate strings with a blazing fast speed", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer another_command.deinit();

    try std.testing.expectError(CommandAddError.CommandNameAlreadyExists, commands.add_disallow_child(another_command, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.CommandNameAlreadyExists;
    try std.testing.expectEqualStrings("stringer", diagnostics_type.command);
}

test "attempt to add a command with an existing alias" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var command = Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    command.addAliases(&[_]CommandAlias{"str"});

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(command, &diagnostics);

    var another_command = Command.init("fast string", "manipulate strings with a blazing fast speed", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    another_command.addAliases(&[_]CommandAlias{"str"});
    defer another_command.deinit();

    try std.testing.expectError(CommandAddError.CommandAliasAlreadyExists, commands.add_disallow_child(another_command, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.CommandAliasAlreadyExists;
    try std.testing.expectEqualStrings("str", diagnostics_type.alias);
    try std.testing.expectEqualStrings("stringer", diagnostics_type.existing_command);
}

test "execute a command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            add_command_result = augend + addend;
            return;
        }
    }.run;

    const command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5" });
    try commands.execute(&arguments, &diagnostics);

    try std.testing.expectEqual(7, add_command_result);
}

test "execute help command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var add_command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    add_command.addAliases(&[_][]const u8{"plus"});

    var subtract_command = Command.init("sub", "subtract numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    subtract_command.addAliases(&[_][]const u8{"minus"});

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var commands = Commands.init(std.testing.allocator, output_stream);
    defer commands.deinit();

    try commands.addHelp();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(add_command, &diagnostics);
    try commands.add_disallow_child(subtract_command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{"help"});
    try commands.execute(&arguments, &diagnostics);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "add").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "plus").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "sub").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "minus").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "-h").? > 0);
}

test "execute a command with a subcommand by adding the parent command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            get_command_result = arguments[0];
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var get_command = Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(kubectl_command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods" });
    try commands.execute(&arguments, &diagnostics);

    try std.testing.expectEqualStrings("pods", get_command_result);
}

test "attempt to execute a command with an unregistered command from command line" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    command.setArgumentSpecification(ArgumentSpecification.mustBeMaximum(3));

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "subtract", "2", "4" });
    try std.testing.expectError(CommandExecutionError.CommandNotFound, commands.execute(&arguments, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.CommandNotFound;
    try std.testing.expectEqualStrings("subtract", diagnostics_type.command);
}

test "attempt to execute a command with mismatch in argument specification" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    command.setArgumentSpecification(ArgumentSpecification.mustBeMaximum(3));

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "6", "3" });
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsGreaterThanMaximum, commands.execute(&arguments, &diagnostics));
}
