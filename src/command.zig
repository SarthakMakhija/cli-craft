const CommandAction = @import("command-action.zig").CommandAction;

pub const CommandFn = *const fn () anyerror!void;
pub const CommandAlias = []const u8;
pub const CommandAliases = []const CommandAlias;

pub const Command = struct {
    name: []const u8,
    description: []const u8,
    action: CommandAction,
    aliases: ?CommandAliases = null,
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

    pub fn addAliases(self: *Command, aliases: CommandAliases) Command {
        self.aliases = aliases;
        return self.*;
    }

    pub fn addSubcommand(self: *Command, subcommand: *Command) !void {
        subcommand.has_parent = true;
        try self.action.addSubcommand(subcommand.*);
    }
};

const std = @import("std");

test "initialize a command with an executable action" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    const command = Command.init("test", "test command", runnable);

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
    _ = command.addAliases(&[_]CommandAlias{"str"});

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
    _ = command.addAliases(&[_]CommandAlias{ "str", "strm" });

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
    defer kubectl_command.action.deinit();

    var get_command = Command.init("get", "get objects", runnable);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(kubectl_command.action.subcommands.get("get") != null);
    try std.testing.expectEqualStrings("get", kubectl_command.action.subcommands.get("get").?.name);
}
