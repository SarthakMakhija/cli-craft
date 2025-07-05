const std = @import("std");

const Command = @import("command.zig").Command;
const CommandFnArguments = @import("command.zig").CommandFnArguments;
const Commands = @import("commands.zig").Commands;
const CommandFn = @import("command.zig").CommandFn;
const ParsedFlags = @import("flags.zig").ParsedFlags;

pub const CommanAddError = error{CannotAddSubCommandToExecutable};

pub const CommandAction = union(enum) {
    executable: CommandFn,
    subcommands: Commands,

    pub fn initExecutable(executable: CommandFn) CommandAction {
        return .{ .executable = executable };
    }

    pub fn initSubcommands(allocator: std.mem.Allocator) !CommandAction {
        return .{ .subcommands = Commands.init(allocator) };
    }

    pub fn addSubcommand(self: *CommandAction, subcommand: Command) !void {
        switch (self.*) {
            .executable => {
                return CommanAddError.CannotAddSubCommandToExecutable;
            },
            .subcommands => {
                try self.subcommands.add_allow_parent(subcommand);
            },
        }
    }

    pub fn deinit(self: *CommandAction) void {
        switch (self.*) {
            .executable => {},
            .subcommands => self.subcommands.deinit(),
        }
    }
};

test "add an executable" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command_action = CommandAction.initExecutable(runnable);
    defer command_action.deinit();

    try std.testing.expect(command_action.executable == runnable);
}

test "add a sub-command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    const command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    var command_action = try CommandAction.initSubcommands(std.testing.allocator);
    defer command_action.deinit();

    try command_action.addSubcommand(command);

    const retrieved = command_action.subcommands.get("stringer");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("stringer", retrieved.?.name);
}
