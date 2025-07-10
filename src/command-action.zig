const std = @import("std");

const Command = @import("commands.zig").Command;
const CommandFnArguments = @import("commands.zig").CommandFnArguments;
const Commands = @import("commands.zig").Commands;
const CommandFn = @import("commands.zig").CommandFn;
const ParsedFlags = @import("flags.zig").ParsedFlags;

pub const CommandAddError = error{CannotAddSubCommandToExecutable};

const ErrorLog = @import("log.zig").ErrorLog;

pub const CommandAction = union(enum) {
    executable: CommandFn,
    subcommands: Commands,

    pub fn initExecutable(executable: CommandFn) CommandAction {
        return .{ .executable = executable };
    }

    pub fn initSubcommands(allocator: std.mem.Allocator, error_log: ErrorLog) !CommandAction {
        return .{ .subcommands = Commands.init(allocator, error_log) };
    }

    pub fn addSubcommand(self: *CommandAction, subcommand: Command, error_log: ErrorLog) !void {
        switch (self.*) {
            .executable => {
                error_log.log("Error: Subcommand '{s}' added to an excutable command.\n", .{subcommand.name});
                return CommandAddError.CannotAddSubCommandToExecutable;
            },
            .subcommands => {
                try self.subcommands.add_allow_child(subcommand);
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

    var command_action = try CommandAction.initSubcommands(std.testing.allocator, ErrorLog.initNoOperation());
    defer command_action.deinit();

    try command_action.addSubcommand(command, command.error_log);

    const retrieved = command_action.subcommands.get("stringer");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("stringer", retrieved.?.name);
}

test "attempt to add a sub-command to an executable command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    const command = Command.init("stringer", "manipulate strings", runnable, std.testing.allocator);
    var command_action = CommandAction.initExecutable(runnable);
    defer command_action.deinit();

    try std.testing.expectError(CommandAddError.CannotAddSubCommandToExecutable, command_action.addSubcommand(command, command.error_log));
}
