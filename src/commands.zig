const std = @import("std");
const Sort = std.sort;

const Command = @import("command.zig").Command;
const CommandFnArguments = @import("command.zig").CommandFnArguments;
const CommandAlias = @import("command.zig").CommandAlias;
const Arguments = @import("arguments.zig").Arguments;
const StringDistance = @import("string-distance.zig").StringDistance;
const ParsedFlags = @import("flags.zig").ParsedFlags;

const BestDistance = 3;

pub const CommandAddError = error{
    CommandHasAParent,
    CommandNameAlreadyExists,
    CommandAliasAlreadyExists,
};

pub const CommandExecutionError = error{
    MissingCommandNameToExecute,
    CommandNotAdded,
};

pub const CommandSuggestion = struct {
    name: []const u8,
    distance: u16,
};

pub const Commands = struct {
    commands: std.StringHashMap(Command),
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
    ) Commands {
        return .{
            .commands = std.StringHashMap(Command).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn add_allow_parent(self: *Commands, command: Command) !void {
        return try self.add(command, true);
    }

    pub fn add_disallow_parent(self: *Commands, command: Command) !void {
        return try self.add(command, false);
    }

    pub fn get(self: Commands, name: []const u8) ?Command {
        return self.commands.get(name);
    }

    pub fn deinit(self: *Commands) void {
        var iterator = self.commands.valueIterator();
        while (iterator.next()) |command| {
            command.deinit();
        }
        self.commands.deinit();
    }

    fn add(
        self: *Commands,
        command: Command,
        allow_parent: bool,
    ) !void {
        if (!allow_parent and command.has_parent) {
            return CommandAddError.CommandHasAParent;
        }
        const name = command.name;
        try self.ensureCommandDoesNotExist(command);
        try self.commands.put(name, command);
        if (command.aliases) |aliases| {
            for (aliases) |alias| {
                try self.commands.put(alias, command);
            }
        }
    }

    fn execute(self: Commands, arguments: *Arguments) !void {
        const command_name = arguments.next() orelse return CommandExecutionError.MissingCommandNameToExecute;
        const command = self.get(command_name) orelse return CommandExecutionError.CommandNotAdded;

        return try command.execute(arguments, self.allocator);
    }

    fn suggestions_for(self: Commands, name: []const u8) !std.ArrayList(CommandSuggestion) {
        var suggestions = std.ArrayList(CommandSuggestion).init(self.allocator);
        var command_names = self.commands.keyIterator();

        while (command_names.next()) |command_name| {
            const distance = try StringDistance.levenshtein(self.allocator, name, command_name.*);
            if (distance <= BestDistance) {
                try suggestions.append(.{
                    .name = command_name.*,
                    .distance = distance,
                });
            }
        }

        std.mem.sort(CommandSuggestion, suggestions.items, {}, struct {
            fn compare(_: void, first: CommandSuggestion, second: CommandSuggestion) bool {
                return first.distance < second.distance;
            }
        }.compare);

        return suggestions;
    }

    fn ensureCommandDoesNotExist(self: Commands, command: Command) !void {
        if (self.commands.contains(command.name)) {
            return CommandAddError.CommandNameAlreadyExists;
        }
        if (command.aliases) |aliases| {
            for (aliases) |alias| {
                if (self.commands.contains(alias)) {
                    return CommandAddError.CommandAliasAlreadyExists;
                }
            }
        }
        return;
    }
};

const ArgumentSpecification = @import("argument-specification.zig").ArgumentSpecification;
const ArgumentSpecificationError = @import("argument-specification.zig").ArgumentSpecificationError;

test "attempt to add a command which has a parent" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = Command.init("get", "get objects", runnable, std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try std.testing.expectError(CommandAddError.CommandHasAParent, commands.add_disallow_parent(get_command));
}

test "add a command which has a child" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", std.testing.allocator);

    var get_command = Command.init("get", "get objects", runnable, std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(kubectl_command);
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

    const command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(command);
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

    var command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    command.addAliases(&[_]CommandAlias{"str"});

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(command);
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

    var command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(command);
    try std.testing.expectEqualStrings("stringer", commands.get("str").?.name);
    try std.testing.expectEqualStrings("stringer", commands.get("strm").?.name);
}

test "attempt to add a command with an existing name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    const command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    try commands.add_disallow_parent(command);

    const another_command = Command.init("stringer", "manipulate strings with a blazing fast speed", runnable, std.testing.allocator);
    try std.testing.expectError(CommandAddError.CommandNameAlreadyExists, commands.add_disallow_parent(another_command));
}

test "attempt to add a command with an existing alias" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    var command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    command.addAliases(&[_]CommandAlias{"str"});

    try commands.add_disallow_parent(command);

    var another_command = Command.init("fast string", "manipulate strings with a blazing fast speed", runnable, std.testing.allocator);
    another_command.addAliases(&[_]CommandAlias{"str"});
    defer another_command.deinit();

    try std.testing.expectError(CommandAddError.CommandAliasAlreadyExists, commands.add_disallow_parent(another_command));
}

test "get suggestions for a command (1)" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(Command.init("stringer", "manipulate strings", runnable, std.testing.allocator));
    try commands.add_disallow_parent(Command.init("str", "short for stringer", runnable, std.testing.allocator));
    try commands.add_disallow_parent(Command.init("strm", "short for stringer", runnable, std.testing.allocator));

    var suggestions = try commands.suggestions_for("strn");
    defer suggestions.deinit();

    try std.testing.expectEqual(2, suggestions.items.len);
    try std.testing.expectEqualStrings("str", suggestions.pop().?.name);
    try std.testing.expectEqualStrings("strm", suggestions.pop().?.name);
}

test "get suggestions for a command (2)" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(Command.init("stringer", "manipulate strings", runnable, std.testing.allocator));
    try commands.add_disallow_parent(Command.init("str", "short for stringer", runnable, std.testing.allocator));
    try commands.add_disallow_parent(Command.init("zig", "language", runnable, std.testing.allocator));

    var suggestions = try commands.suggestions_for("string");
    defer suggestions.deinit();

    try std.testing.expectEqual(2, suggestions.items.len);
    try std.testing.expectEqualStrings("str", suggestions.pop().?.name);
    try std.testing.expectEqualStrings("stringer", suggestions.pop().?.name);
}

var add_command_result: u8 = undefined;
var get_command_result: []const u8 = undefined;

test "execute a command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            add_command_result = augend + addend;
            return;
        }
    }.run;

    const command = Command.init("add", "add numbers", runnable, std.testing.allocator);

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5" });
    try commands.execute(&arguments);

    try std.testing.expectEqual(7, add_command_result);
}

test "execute a command with a subcommand" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            get_command_result = arguments[0];
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", std.testing.allocator);

    var get_command = Command.init("get", "get objects", runnable, std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(kubectl_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods" });
    try commands.execute(&arguments);

    try std.testing.expectEqualStrings("pods", get_command_result);
}

test "attempt to execute a command with mismatch in argument specification" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("add", "add numbers", runnable, std.testing.allocator);
    command.setArgumentSpecification(ArgumentSpecification.mustBeMaximum(3));

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "6", "3" });
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsGreaterThanMaximum, commands.execute(&arguments));
}
