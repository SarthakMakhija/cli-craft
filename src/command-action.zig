const std = @import("std");

const Command = @import("commands.zig").Command;
const CommandFnArguments = @import("commands.zig").CommandFnArguments;
const Commands = @import("commands.zig").Commands;
const CommandAddError = @import("commands.zig").CommandAddError;
const CommandFn = @import("commands.zig").CommandFn;
const ParsedFlags = @import("flags.zig").ParsedFlags;

const Diagnostics = @import("diagnostics.zig").Diagnostics;
const OutputStream = @import("stream.zig").OutputStream;

/// Defines the action a `Command` can perform: either executing a function or managing a
/// collection of subcommands.
/// This union ensures that a command can only have one type of action, preventing conflicting behaviors.
pub const CommandAction = union(enum) {
    /// The command executes a specific function when invoked.
    executable: CommandFn,
    /// The command acts as a container for other subcommands.
    subcommands: Commands,

    /// Initializes a `CommandAction` as an executable function.
    ///
    /// Parameters:
    ///   executable: The `CommandFn` to be associated with this action.
    pub fn initExecutable(executable: CommandFn) CommandAction {
        return .{ .executable = executable };
    }

    /// Initializes a `CommandAction` as a container for subcommands.
    ///
    /// This creates an empty `Commands` collection to hold the subcommands.
    ///
    /// Parameters:
    ///   allocator: The allocator to use for the internal `Commands` collection.
    ///   output_stream: The `OutputStream` to pass to the internal `Commands` collection.
    ///
    /// Returns:
    ///   A new `CommandAction` configured for subcommands.
    pub fn initSubcommands(allocator: std.mem.Allocator, output_stream: OutputStream) !CommandAction {
        return .{ .subcommands = Commands.init(allocator, output_stream) };
    }

    /// Adds a subcommand to this `CommandAction` if it is configured for subcommands.
    ///
    /// This method performs validation checks, such as ensuring the subcommand name
    /// is not the same as the parent command's name, and preventing subcommands
    /// from being added to executable commands. It also sets the `has_parent`
    /// flag on the subcommand.
    ///
    /// Parameters:
    ///   self: A pointer to the `CommandAction` instance.
    ///   parent_command: A pointer to the parent `Command` struct.
    ///   subcommand: A pointer to the `Command` struct to be added as a subcommand.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on success, or an error if the subcommand cannot be added due to validation rules.
    pub fn addSubcommand(
        self: *CommandAction,
        parent_command: *Command,
        subcommand: *Command,
        diagnostics: *Diagnostics,
    ) !void {
        if (std.mem.eql(u8, subcommand.name, parent_command.name)) {
            return diagnostics.reportAndFail(.{
                .SubCommandNameSameAsParent = .{ .command = subcommand.name },
            });
        }
        switch (self.*) {
            .executable => {
                return diagnostics.reportAndFail(.{
                    .SubCommandAddedToExecutable = .{
                        .command = parent_command.name,
                        .subcommand = subcommand.name,
                    },
                });
            },
            .subcommands => {
                subcommand.has_parent = true;
                try self.subcommands.add_allow_child(subcommand, diagnostics);
            },
        }
    }

    /// Deinitializes the `CommandAction`, freeing any associated resources.
    ///
    /// If the action is `subcommands`, it will deinitialize the internal `Commands` collection.
    /// For `executable` actions, there are no resources to free.
    ///
    /// Parameters:
    ///   self: A pointer to the `CommandAction` instance.
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

    var parent_command = try Command.initParent(
        "strings",
        "collection of string utilities",
        OutputStream.initNoOperationOutputStream(),
        std.testing.allocator,
    );
    defer parent_command.deinit();

    var command = try Command.init(
        "stringer",
        "manipulate strings",
        runnable,
        OutputStream.initNoOperationOutputStream(),
        std.testing.allocator,
    );

    var command_action = try CommandAction.initSubcommands(
        std.testing.allocator,
        OutputStream.initNoOperationOutputStream(),
    );
    defer command_action.deinit();

    var diagnostics: Diagnostics = .{};
    try command_action.addSubcommand(
        &parent_command,
        &command,
        &diagnostics,
    );

    const retrieved = command_action.subcommands.get("stringer");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("stringer", retrieved.?.name);
}

test "attempt to initialize a parent command with a subcommand having the same name as parent command name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var parent_command = try Command.initParent(
        "kubectl",
        "kubernetes entry point",
        OutputStream.initNoOperationOutputStream(),
        std.testing.allocator,
    );
    defer parent_command.deinit();

    var command_action = try CommandAction.initSubcommands(
        std.testing.allocator,
        OutputStream.initNoOperationOutputStream(),
    );
    defer command_action.deinit();

    var get_command = try Command.init(
        "kubectl",
        "get objects",
        runnable,
        OutputStream.initNoOperationOutputStream(),
        std.testing.allocator,
    );
    defer get_command.deinit();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(
        CommandAddError.SubCommandNameSameAsParent,
        command_action.addSubcommand(
            &parent_command,
            &get_command,
            &diagnostics,
        ),
    );

    const diagnostic_type = diagnostics.diagnostics_type.?.SubCommandNameSameAsParent;
    try std.testing.expectEqualStrings("kubectl", diagnostic_type.command);
}

test "attempt to add a sub-command to an executable command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var parent_command = try Command.init(
        "stringer",
        "manipulate strings",
        runnable,
        OutputStream.initNoOperationOutputStream(),
        std.testing.allocator,
    );
    defer parent_command.deinit();

    var command = try Command.init(
        "reverse",
        "reverse string",
        runnable,
        OutputStream.initNoOperationOutputStream(),
        std.testing.allocator,
    );
    defer command.deinit();

    var command_action = CommandAction.initExecutable(runnable);
    defer command_action.deinit();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(CommandAddError.SubCommandAddedToExecutable, command_action.addSubcommand(
        &parent_command,
        &command,
        &diagnostics,
    ));

    const diagnostic_type = diagnostics.diagnostics_type.?.SubCommandAddedToExecutable;
    try std.testing.expectEqualStrings("stringer", diagnostic_type.command);
    try std.testing.expectEqualStrings("reverse", diagnostic_type.subcommand);
}
