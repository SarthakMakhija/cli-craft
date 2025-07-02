pub const CommandAlias = []const u8;
pub const CommandFn = *const fn () anyerror!void;
pub const CommandAliases = []const CommandAlias;

pub const Command = struct {
    name: []const u8,
    description: []const u8,
    executable: CommandFn,
    aliases: ?CommandAliases = null,

    pub fn init(name: []const u8, description: []const u8, executable: CommandFn) Command {
        return .{
            .name = name,
            .description = description,
            .executable = executable,
        };
    }

    pub fn addAliases(self: *Command, aliases: CommandAliases) Command {
        self.aliases = aliases;
        return self.*;
    }
};

const std = @import("std");

test "initialize a command" {
    const runnable = struct {
        pub fn run() anyerror!void {
            return;
        }
    }.run;

    const command = Command.init("test", "test command", runnable);

    try std.testing.expectEqualStrings("test", command.name);
    try std.testing.expectEqualStrings("test command", command.description);
}

test "initialize a command with an alias" {
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

test "initialize a command with a couple of aliases" {
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
