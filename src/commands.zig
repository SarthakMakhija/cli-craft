const std = @import("std");
const Sort = std.sort;

const Command = @import("command.zig").Command;
const CommandAlias = @import("command.zig").CommandAlias;
const StringDistance = @import("string-distance.zig").StringDistance;

const BestDistance = 3;

pub const CommandAddError = error{
    CommandHasAParent,
    CommandNameAlreadyExists,
    CommandAliasAlreadyExists,
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
        return self.add(command, true);
    }

    pub fn add_disallow_parent(self: *Commands, command: Command) !void {
        return self.add(command, false);
    }

    pub fn get(self: Commands, name: []const u8) ?Command {
        return self.commands.get(name);
    }

    pub fn deinit(self: *Commands) void {
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

test "attempt to add a command which has a parent" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", std.testing.allocator);
    defer kubectl_command.action.deinit();

    var get_command = Command.init("get", "get objects", runnable);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    commands.add_disallow_parent(get_command) catch |err| {
        try std.testing.expectEqual(CommandAddError.CommandHasAParent, err);
    };
}

test "add a command which has a child" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", std.testing.allocator);
    defer kubectl_command.action.deinit();

    var get_command = Command.init("get", "get objects", runnable);
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
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    const command = Command.init("stringer", "manipulate strings", runnable);
    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(command);
    const retrieved = commands.get("stringer");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("stringer", retrieved.?.name);
}

test "add a command with a name and an alias" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable);
    _ = command.addAliases(&[_]CommandAlias{"str"});

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(command);
    const retrieved = commands.get("str");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("stringer", retrieved.?.name);
}

test "add a command with a name and a couple of aliases" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable);
    _ = command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(command);
    try std.testing.expectEqualStrings("stringer", commands.get("str").?.name);
    try std.testing.expectEqualStrings("stringer", commands.get("strm").?.name);
}

test "attempt to add a command with an existing name" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    const command = Command.init("stringer", "manipulate strings", runnable);
    try commands.add_disallow_parent(command);

    const another_command = Command.init("stringer", "manipulate strings with a blazing fast speed", runnable);
    commands.add_disallow_parent(another_command) catch |err| {
        try std.testing.expectEqual(CommandAddError.CommandNameAlreadyExists, err);
    };
}

test "attempt to add a command with an existing alias" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    var command = Command.init("stringer", "manipulate strings", runnable);
    _ = command.addAliases(&[_]CommandAlias{"str"});

    try commands.add_disallow_parent(command);

    var another_command = Command.init("fast string", "manipulate strings with a blazing fast speed", runnable);
    _ = another_command.addAliases(&[_]CommandAlias{"str"});

    commands.add_disallow_parent(another_command) catch |err| {
        try std.testing.expectEqual(CommandAddError.CommandAliasAlreadyExists, err);
    };
}

test "get suggestions for a command (1)" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(Command.init("stringer", "manipulate strings", runnable));
    try commands.add_disallow_parent(Command.init("str", "short for stringer", runnable));
    try commands.add_disallow_parent(Command.init("strm", "short for stringer", runnable));

    var suggestions = try commands.suggestions_for("strn");
    defer suggestions.deinit();

    try std.testing.expectEqual(2, suggestions.items.len);
    try std.testing.expectEqualStrings("str", suggestions.pop().?.name);
    try std.testing.expectEqualStrings("strm", suggestions.pop().?.name);
}

test "get suggestions for a command (2)" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add_disallow_parent(Command.init("stringer", "manipulate strings", runnable));
    try commands.add_disallow_parent(Command.init("str", "short for stringer", runnable));
    try commands.add_disallow_parent(Command.init("zig", "language", runnable));

    var suggestions = try commands.suggestions_for("string");
    defer suggestions.deinit();

    try std.testing.expectEqual(2, suggestions.items.len);
    try std.testing.expectEqualStrings("str", suggestions.pop().?.name);
    try std.testing.expectEqualStrings("stringer", suggestions.pop().?.name);
}
