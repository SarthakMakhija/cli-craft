const CommandAction = @import("command-action.zig").CommandAction;
const ArgumentSpecification = @import("argument-specification.zig").ArgumentSpecification;
const Arguments = @import("arguments.zig").Arguments;

pub const CommandFn = *const fn () anyerror!void;
pub const CommandAlias = []const u8;
pub const CommandAliases = []const CommandAlias;

pub const CommandExecutionError = error{
    NoSubcommandProvided,
    SubcommandNotAddedToParentCommand,
};

pub const Command = struct {
    name: []const u8,
    description: []const u8,
    action: CommandAction,
    aliases: ?CommandAliases = null,
    argument_specification: ?ArgumentSpecification = null,
    has_parent: bool = false,

    pub fn init(name: []const u8, description: []const u8, executable: CommandFn) Command {
        return .{
            .name = name,
            .description = description,
            .action = CommandAction.initExecutable(executable),
        };
    }

    pub fn initParent(name: []const u8, description: []const u8, allocator: std.mem.Allocator) !Command {
        return .{
            .name = name,
            .description = description,
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

    pub fn deinit(self: *Command) void {
        self.action.deinit();
    }

    fn execute(self: Command, arguments: *Arguments) anyerror!void {
        switch (self.action) {
            .executable => |executable_fn| {
                return executable_fn();
            },
            .subcommands => |sub_commands| {
                const subcommand_name = arguments.next() orelse return CommandExecutionError.NoSubcommandProvided;
                const command = sub_commands.get(subcommand_name) orelse return CommandExecutionError.SubcommandNotAddedToParentCommand;

                return command.execute(arguments);
            },
        }
    }
};

const std = @import("std");

test "initialize a command with an executable action" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("test", "test command", runnable);
    defer command.deinit();

    try std.testing.expectEqualStrings("test", command.name);
    try std.testing.expectEqualStrings("test command", command.description);
}

test "initialize an executable command with an alias" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable);
    command.addAliases(&[_]CommandAlias{"str"});

    defer command.deinit();

    try std.testing.expect(command.aliases != null);

    const aliases: CommandAliases = command.aliases.?;

    try std.testing.expectEqual(aliases.len, 1);
    try std.testing.expectEqualStrings("str", aliases[0]);
}

test "initialize an executable command with a couple of aliases" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable);
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
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(kubectl_command.action.subcommands.get("get") != null);
    try std.testing.expectEqualStrings("get", kubectl_command.action.subcommands.get("get").?.name);
}

test "initialize an executable command with argument specification (1)" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable);
    command.setArgumentSpecification(ArgumentSpecification.mustBeMinimum(1));

    defer command.deinit();

    try std.testing.expect(command.argument_specification != null);
    try std.testing.expectEqual(ArgumentSpecification.mustBeMinimum(1), command.argument_specification.?);
}

test "initialize an executable command with argument specification (2)" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable);
    command.setArgumentSpecification(ArgumentSpecification.mustBeInEndInclusiveRange(1, 5));

    defer command.deinit();

    try std.testing.expect(command.argument_specification != null);
    try std.testing.expectEqual(ArgumentSpecification.mustBeInEndInclusiveRange(1, 5), command.argument_specification.?);
}

var add_command_executed = false;
var get_command_executed = false;

test "execute a command with an executable action" {
    const runnable = struct {
        pub fn run() anyerror!void {
            add_command_executed = true;
            return;
        }
    }.run;

    var command = Command.init("add", "add numbers", runnable);
    defer command.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{"add"});
    try command.execute(&arguments);

    try std.testing.expect(add_command_executed);
}

test "execute a command with a subcommand" {
    const runnable = struct {
        pub fn run() anyerror!void {
            get_command_executed = true;
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable);
    defer get_command.deinit();

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get" });
    arguments.skipFirst();

    try kubectl_command.execute(&arguments);

    try std.testing.expect(get_command_executed);
}

test "attempt to execute a command with a subcommand but with incorrect command name from the argument" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable);
    defer get_command.deinit();

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "delete" });
    arguments.skipFirst();

    try std.testing.expectError(CommandExecutionError.SubcommandNotAddedToParentCommand, kubectl_command.execute(&arguments));
}
