const std = @import("std");

const Command = @import("commands.zig").Command;
const CommandFnArguments = @import("commands.zig").CommandFnArguments;
const Commands = @import("commands.zig").Commands;
const CommandAddError = @import("commands.zig").CommandAddError;
const CommandFn = @import("commands.zig").CommandFn;
const ParsedFlags = @import("flags.zig").ParsedFlags;

const Diagnostics = @import("diagnostics.zig").Diagnostics;

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

    pub fn addSubcommand(self: *CommandAction, parent_command_name: []const u8, subcommand: *Command, diagnostics: *Diagnostics) !void {
        if (std.mem.eql(u8, subcommand.name, parent_command_name)) {
            return diagnostics.reportAndFail(.{ .SubCommandNameSameAsParent = .{ .command = subcommand.name } });
        }
        switch (self.*) {
            .executable => {
                return diagnostics.reportAndFail(.{ .SubCommandAddedToExecutable = .{ .command = parent_command_name, .subcommand = subcommand.name } });
            },
            .subcommands => {
                subcommand.has_parent = true;
                try self.subcommands.add_allow_child(subcommand.*, diagnostics);
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

    var command = Command.init("stringer", "manipulate strings", runnable, ErrorLog.initNoOperation(), std.testing.allocator);

    var command_action = try CommandAction.initSubcommands(std.testing.allocator, ErrorLog.initNoOperation());
    defer command_action.deinit();

    var diagnostics: Diagnostics = .{};
    try command_action.addSubcommand("strings", &command, &diagnostics);

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

    var command = Command.init("stringer", "manipulate strings", runnable, ErrorLog.initNoOperation(), std.testing.allocator);
    defer command.deinit();

    var command_action = CommandAction.initExecutable(runnable);
    defer command_action.deinit();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(CommandAddError.SubCommandAddedToExecutable, command_action.addSubcommand("strings", &command, &diagnostics));

    const diagnostic_type = diagnostics.diagnostics_type.?.SubCommandAddedToExecutable;
    try std.testing.expectEqualStrings("strings", diagnostic_type.command);
    try std.testing.expectEqualStrings("stringer", diagnostic_type.subcommand);
}

test "attempt to initialize a parent command with a subcommand having the same name as parent command name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command_action = try CommandAction.initSubcommands(std.testing.allocator, ErrorLog.initNoOperation());
    defer command_action.deinit();

    var get_command = Command.init("kubectl", "get objects", runnable, ErrorLog.initNoOperation(), std.testing.allocator);
    defer get_command.deinit();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(CommandAddError.SubCommandNameSameAsParent, command_action.addSubcommand("kubectl", &get_command, &diagnostics));

    const diagnostic_type = diagnostics.diagnostics_type.?.SubCommandNameSameAsParent;
    try std.testing.expectEqualStrings("kubectl", diagnostic_type.command);
}
