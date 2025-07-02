const std = @import("std");

const Command = @import("command.zig").Command;
const CommandAlias = @import("command.zig").CommandAlias;
const StringDistance = @import("string-distance.zig").StringDistance;

const CommandAddError = error{
    CommandNameAlreadyExists,
    CommandAliasAlreadyExists,
};

const Commands = struct {
    commands: std.StringHashMap(Command),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Commands {
        return .{
            .commands = std.StringHashMap(Command).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn add(self: *Commands, command: Command) !void {
        const name = command.name;
        try self.ensureCommandDoesNotExist(command);
        try self.commands.put(name, command);
        if (command.aliases) |aliases| {
            for (aliases) |alias| {
                try self.commands.put(alias, command);
            }
        }
    }

    pub fn get(self: Commands, name: []const u8) ?Command {
        return self.commands.get(name);
    }

    fn suggestion_for(self: Commands, name: []const u8) !?[]const u8 {
        var best_distance: u16 = 0;
        var best_suggestion: ?[]const u8 = null;

        var command_names = self.commands.keyIterator();
        while (command_names.next()) |command_name| {
            const distance = try StringDistance.levenshtein(self.allocator, name, command_name.*);
            if (best_suggestion == null or distance < best_distance) {
                best_distance = distance;
                best_suggestion = command_name.*;
            }
        }
        return best_suggestion;
    }

    pub fn deinit(self: *Commands) void {
        self.commands.deinit();
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

test "add a command with a name" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    const command = Command.init("stringer", "manipulate strings", runnable);
    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add(command);
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

    try commands.add(command);
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

    try commands.add(command);
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
    try commands.add(command);

    const another_command = Command.init("stringer", "manipulate strings with a blazing fast speed", runnable);
    commands.add(another_command) catch |err| {
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

    try commands.add(command);

    var another_command = Command.init("fast string", "manipulate strings with a blazing fast speed", runnable);
    _ = another_command.addAliases(&[_]CommandAlias{"str"});

    commands.add(another_command) catch |err| {
        try std.testing.expectEqual(CommandAddError.CommandAliasAlreadyExists, err);
    };
}

test "get suggestion for a command (1)" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add(Command.init("stringer", "manipulate strings", runnable));
    try commands.add(Command.init("str", "short for stringer", runnable));
    try commands.add(Command.init("strm", "short for stringer", runnable));

    const suggestion = try commands.suggestion_for("strn");
    try std.testing.expect(suggestion != null);
    try std.testing.expectEqualStrings("strm", suggestion.?);
}

test "get suggestion for a command (2)" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator);
    defer commands.deinit();

    try commands.add(Command.init("stringer", "manipulate strings", runnable));
    try commands.add(Command.init("str", "short for stringer", runnable));
    try commands.add(Command.init("strm", "short for stringer", runnable));

    const suggestion = try commands.suggestion_for("string");
    try std.testing.expect(suggestion != null);
    try std.testing.expectEqualStrings("stringer", suggestion.?);
}
