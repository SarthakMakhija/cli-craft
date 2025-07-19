const std = @import("std");

const CommandAction = @import("command-action.zig").CommandAction;
const Arguments = @import("arguments.zig").Arguments;
const Flags = @import("flags.zig").Flags;
const Flag = @import("flags.zig").Flag;
const FlagType = @import("flags.zig").FlagType;
const FlagValue = @import("flags.zig").FlagValue;
const FlagErrors = @import("flags.zig").FlagErrors;
const Diagnostics = @import("diagnostics.zig").Diagnostics;

const ParsedFlags = @import("flags.zig").ParsedFlags;
const ParsedFlag = @import("flags.zig").ParsedFlag;

const CommandLineParser = @import("command-line-parser.zig").CommandLineParser;
const CommandParsingError = @import("command-line-parser.zig").CommandParsingError;

const CommandsHelp = @import("help.zig").CommandsHelp;
const CommandHelp = @import("help.zig").CommandHelp;
const OutputStream = @import("stream.zig").OutputStream;

const prettytable = @import("prettytable");

/// The standard name for the built-in help command.
pub const HelpCommandName = "help";

/// Errors that can occur when adding commands or subcommands to the CLI structure.
pub const CommandAddError = error{
    /// An attempt was made to add a child command directly to the top-level CLI.
    ChildCommandAdded,
    /// A command with the same name already exists.
    CommandNameAlreadyExists,
    /// A command alias already exists for another command.
    CommandAliasAlreadyExists,
    /// An attempt was made to add a subcommand to a command defined as executable.
    SubCommandAddedToExecutable,
    /// A subcommand's name is identical to its parent command's name.
    SubCommandNameSameAsParent,
};

/// Errors related to attempting to modify a command after it has been "frozen".
pub const CommandMutationError = error{
    /// An attempt was made to modify a command after it has been frozen (added to the CLI structure
    /// or a command is added to a parent command).
    CommandAlreadyFrozen,
};

/// Errors that can occur during the execution phase of commands.
pub const CommandExecutionError = error{
    /// No command name was provided for execution.
    MissingCommandNameToExecute,
    /// A specified command was not found.
    CommandNotFound,
};

/// A union of all possible errors related to command operations.
pub const CommandErrors = CommandAddError || CommandExecutionError || CommandParsingError || CommandMutationError;

/// Type alias for the arguments passed to a command's executable function.
pub const CommandFnArguments = [][]const u8;
/// Type alias for a command's executable function.
/// It takes `parsed_flags` and `parsed_arguments` as input and can return anyerror.
pub const CommandFn = *const fn (flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void;
/// Type alias for a single command alias (a string slice).
pub const CommandAlias = []const u8;
/// Type alias for a slice of command aliases.
pub const CommandAliases = []const CommandAlias;

/// Represents a single command in the CLI application.
/// A command can be either executable or a parent for subcommands.
/// It encapsulates its name, description, action, associated flags, and argument specifications.
/// Command is a mutable concept with methods like setUsage(..), setArgumentSpecification(..) etc.
/// However, a command is frozen after it is added to the CLI structure (Commands) or a subcommand is frozen
/// after it is added to a parent command.
/// Any mutations on a frozen command result in an error.
pub const Command = struct {
    /// The primary name of the command.
    name: []const u8,
    /// A brief description of the command's purpose.
    description: []const u8,
    /// The allocator used for managing the command's internal string data and collections.
    allocator: std.mem.Allocator,
    /// The action this command performs: either executable or a container for subcommands.
    action: CommandAction,
    /// An optional list of alternative names for this command.
    aliases: ?std.ArrayList(CommandAlias) = null,
    /// An optional specification defining the expected number and types of positional arguments.
    argument_specification: ?ArgumentSpecification = null,
    /// A boolean indicating if this command is a subcommand (i.e., has a parent command).
    has_parent: bool = false,
    /// A boolean indicating if this command has been "frozen" and can no longer be modified.
    frozen: bool = false,
    /// Flags that are local to this command and are not inherited by its subcommands.
    local_flags: Flags,
    /// Flags that are persistent and are inherited by this command's subcommands.
    persistent_flags: ?Flags = null,
    /// The output stream to which this command directs its output and errors.
    output_stream: OutputStream,
    /// An optional custom usage string for this command, overriding the default generated one.
    usage: ?[]const u8 = null,

    /// Initializes a new executable command.
    ///
    /// This creates a command that, when invoked, will execute the provided `CommandFn`.
    /// It automatically adds a default 'help' flag to the command's local flags.
    ///
    /// Parameters:
    ///   name: The primary name of the command.
    ///   description: A brief description of the command.
    ///   executable: The function to execute when the command is run.
    ///   output_stream: The output stream for this command.
    ///   allocator: The allocator to use for command's internal data.
    ///
    /// Returns:
    ///   A new `Command` instance configured as executable.
    pub fn init(name: []const u8, description: []const u8, executable: CommandFn, output_stream: OutputStream, allocator: std.mem.Allocator) !Command {
        const cloned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(cloned_name);

        const cloned_description = try allocator.dupe(u8, description);
        errdefer allocator.free(cloned_description);

        var local_flags = Flags.init(allocator);
        try local_flags.addHelp();

        return .{
            .name = cloned_name,
            .description = cloned_description,
            .allocator = allocator,
            .action = CommandAction.initExecutable(executable),
            .output_stream = output_stream,
            .local_flags = local_flags,
        };
    }

    /// Initializes a new parent command (a command that can contain subcommands).
    ///
    /// This creates a command that acts as a container for other commands.
    /// It automatically adds a default 'help' flag to the command's local flags.
    ///
    /// Parameters:
    ///   name: The primary name of the parent command.
    ///   description: A brief description of the parent command.
    ///   output_stream: The output stream for this command.
    ///   allocator: The allocator to use for command's internal data.
    ///
    /// Returns:
    ///   A new `Command` instance configured as a parent.
    pub fn initParent(name: []const u8, description: []const u8, output_stream: OutputStream, allocator: std.mem.Allocator) !Command {
        const cloned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(cloned_name);

        const cloned_description = try allocator.dupe(u8, description);
        errdefer allocator.free(cloned_description);

        var local_flags = Flags.init(allocator);
        try local_flags.addHelp();

        return .{
            .name = cloned_name,
            .description = cloned_description,
            .allocator = allocator,
            .action = try CommandAction.initSubcommands(allocator, output_stream),
            .output_stream = output_stream,
            .local_flags = local_flags,
        };
    }

    /// Adds a subcommand to this command.
    ///
    /// This method performs various validation checks, including:
    /// - Ensuring the subcommand's name is not the same as the parent's.
    /// - Preventing subcommands from being added to executable commands.
    /// - Checking for flag conflicts between the parent's persistent flags and the subcommand's flags.
    ///
    /// Parameters:
    ///   self: A pointer to the parent `Command` instance.
    ///   subcommand: A pointer to the `Command` instance to add as a subcommand.
    ///
    /// Returns:
    ///   `void` on success, or a `CommandAddError` or `FlagErrors` if a validation fails.
    pub fn addSubcommand(self: *Command, subcommand: *Command) !void {
        var diagnostics: Diagnostics = .{};
        self.determineConflictingFlagsWith(subcommand, &diagnostics) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
        self.action.addSubcommand(self, subcommand, &diagnostics) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    /// Sets aliases for this command.
    ///
    /// Aliases provide alternative names by which the command can be invoked.
    /// This method will duplicate the alias strings using the command's allocator.
    ///
    /// Parameters:
    ///   self: A pointer to the `Command` instance.
    ///   aliases: A slice of `CommandAlias` (string slices) to set as aliases.
    ///
    /// Returns:
    ///   `void` on success, or a `CommandMutationError` if the command is frozen.
    pub fn setAliases(self: *Command, aliases: CommandAliases) !void {
        try self.logOnMutationFailureIfFrozen();
        if (self.aliases == null) {
            self.aliases = std.ArrayList(CommandAlias).init(self.allocator);
        }
        for (aliases) |alias| {
            try self.aliases.?.append(try self.allocator.dupe(u8, alias));
        }
    }

    /// Sets the argument specification for this command.
    ///
    /// The `ArgumentSpecification` defines the expected number of positional arguments.
    ///
    /// Parameters:
    ///   self: A pointer to the `Command` instance.
    ///   specification: The `ArgumentSpecification` to apply.
    ///
    /// Returns:
    ///   `void` on success, or a `CommandMutationError` if the command is frozen.
    pub fn setArgumentSpecification(self: *Command, specification: ArgumentSpecification) !void {
        try self.logOnMutationFailureIfFrozen();
        self.argument_specification = specification;
    }

    /// Sets a custom usage string for this command.
    ///
    /// This string will override the automatically generated usage message in help output.
    /// The string will be duplicated using the command's allocator.
    ///
    /// Parameters:
    ///   self: A pointer to the `Command` instance.
    ///   usage: The custom usage string.
    ///
    /// Returns:
    ///   `void` on success, or a `CommandMutationError` if the command is frozen.
    pub fn setUsage(self: *Command, usage: []const u8) !void {
        try self.logOnMutationFailureIfFrozen();
        self.usage = try self.allocator.dupe(u8, usage);
    }

    /// Adds a flag to this command.
    ///
    /// The flag can be either local or persistent, as determined by `flag.persistent`.
    /// This method performs checks to prevent conflicts with existing flags.
    ///
    /// Parameters:
    ///   self: A pointer to the `Command` instance.
    ///   flag: The `Flag` to add. Ownership of the flag's internal strings is transferred.
    ///
    /// Returns:
    ///   `void` on success, or a `CommandMutationError` if frozen, or `FlagErrors` if a conflict occurs.
    pub fn addFlag(self: *Command, flag: Flag) !void {
        try self.logOnMutationFailureIfFrozen();

        var diagnostics: Diagnostics = .{};
        if (flag.persistent) {
            try self.ensureLocalFlagsDoNotContain(flag);
            self.persistent_flags = self.persistent_flags orelse Flags.init(self.allocator);
            self.persistent_flags.?.addFlag(flag, &diagnostics) catch |err| {
                diagnostics.log_using(self.output_stream);
                return err;
            };
        } else {
            try self.ensurePersistentFlagsDoNotContain(flag);
            self.local_flags.addFlag(flag, &diagnostics) catch |err| {
                diagnostics.log_using(self.output_stream);
                return err;
            };
        }
    }

    /// Prints the aliases of this command to a `prettytable.Table`.
    ///
    /// This is typically used by help generation functions.
    ///
    /// Parameters:
    ///   self: The `Command` instance.
    ///   table: A pointer to the `prettytable.Table` to which aliases will be added.
    ///
    /// Returns:
    ///   `void` on success, or an error if printing to the output stream fails.
    pub fn printAliases(self: Command, table: *prettytable.Table) !void {
        if (self.aliases) |aliases| {
            if (aliases.items.len > 0) {
                try self.output_stream.print("Aliases:\n", .{});
                for (aliases.items) |alias| {
                    try table.addRow(&[_][]const u8{alias});
                }
            }
        }
        try self.output_stream.printTable(table);
    }

    /// Deinitializes the `Command` instance, freeing all associated allocated memory.
    ///
    /// This includes the command's name, description, usage string, action (subcommands if any),
    /// local flags, persistent flags, and aliases.
    /// This should be called when the `Command` instance is no longer needed to prevent memory leaks.
    ///
    /// Parameters:
    ///   self: A pointer to the `Command` instance.
    pub fn deinit(self: *Command) void {
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        if (self.usage) |usage| {
            self.allocator.free(usage);
        }
        self.action.deinit();
        self.local_flags.deinit();
        if (self.persistent_flags) |*flags| {
            flags.deinit();
        }
        if (self.aliases) |aliases| {
            for (aliases.items) |alias| {
                self.allocator.free(alias);
            }
            aliases.deinit();
        }
    }

    /// Freezes the command, preventing any further modifications to its definition.
    ///
    /// This is typically called internally by `CliCraft` or `Commands` once a command
    /// has been added to the CLI structure or a subcommand is added to a parent command.
    ///
    /// Parameters:
    ///   self: A pointer to the `Command` instance.
    fn freeze(self: *Command) void {
        self.frozen = true;
    }

    /// Logs a `CommandMutationError.CommandAlreadyFrozen` diagnostic if the command is frozen.
    ///
    /// This is a convenience helper for mutation methods that need to check the frozen state
    /// and log an error before returning.
    ///
    /// Parameters:
    ///   self: The `Command` instance.
    ///
    /// Returns:
    ///   `void` on success (not frozen), or a `CommandMutationError` if frozen.
    fn logOnMutationFailureIfFrozen(self: Command) !void {
        var diagnostics: Diagnostics = .{};
        self.failIfFrozen(&diagnostics) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    /// Checks if the command is frozen and reports an error via `Diagnostics` if it is.
    ///
    /// Parameters:
    ///   self: The `Command` instance.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` if not frozen, or a `CommandMutationError.CommandAlreadyFrozen` if it is.
    fn failIfFrozen(self: Command, diagnostics: *Diagnostics) !void {
        if (self.frozen) {
            return diagnostics.reportAndFail(.{ .CommandAlreadyFrozen = .{
                .command = self.name,
            } });
        }
    }

    /// Ensures that the provided `flag` does not conflict with any flags already
    /// present in this command's `local_flags` collection.
    ///
    /// This is an internal validation helper.
    ///
    /// Parameters:
    ///   self: The `Command` instance.
    ///   flag: The `Flag` to check against local flags.
    ///
    /// Returns:
    ///   `void` on success (no conflict), or a `FlagErrors` if a conflict is detected.
    fn ensureLocalFlagsDoNotContain(self: Command, flag: Flag) !void {
        var diagnostics: Diagnostics = .{};
        self.local_flags.ensureFlagDoesNotExist(flag, &diagnostics) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    /// Ensures that the provided `flag` does not conflict with any flags already
    /// present in this command's `persistent_flags` collection.
    ///
    /// This is an internal validation helper.
    ///
    /// Parameters:
    ///   self: The `Command` instance.
    ///   flag: The `Flag` to check against persistent flags.
    ///
    /// Returns:
    ///   `void` on success (no conflict), or a `FlagErrors` if a conflict is detected.
    fn ensurePersistentFlagsDoNotContain(self: Command, flag: Flag) !void {
        var diagnostics: Diagnostics = .{};
        if (self.persistent_flags) |persistent_flags| {
            persistent_flags.ensureFlagDoesNotExist(flag, &diagnostics) catch |err| {
                diagnostics.log_using(self.output_stream);
                return err;
            };
        }
    }

    /// Checks if this command is the special "help" command.
    ///
    /// Parameters:
    ///   self: The `Command` instance.
    ///
    /// Returns:
    ///   `true` if the command's name matches `HelpCommandName`, `false` otherwise.
    fn isHelp(self: Command) bool {
        return std.mem.eql(u8, self.name, HelpCommandName);
    }

    /// Determines if there are any flag conflicts between this (parent) command's persistent flags
    /// and the provided subcommand's local or persistent flags.
    ///
    /// This is a crucial validation step when adding subcommands.
    ///
    /// Parameters:
    ///   self: A pointer to the parent `Command` instance.
    ///   subcommand: A pointer to the `Command` instance being added as a subcommand.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting conflicts.
    ///
    /// Returns:
    ///   `void` if no conflicts are found, or a `FlagErrors.FlagConflictDetected` if a conflict exists.
    fn determineConflictingFlagsWith(self: *Command, subcommand: *Command, diagnostics: *Diagnostics) !void {
        if (self.persistent_flags) |persistent_flags| {
            if (subcommand.persistent_flags) |subcommand_persistent_flags| {
                const flag_conflict = persistent_flags.determineConflictWith(subcommand_persistent_flags);
                if (flag_conflict.has_conflict) {
                    return diagnostics.reportAndFail(
                        flag_conflict.diagnostic_type(self.name, subcommand.name),
                    );
                }
            }

            const flag_conflict = persistent_flags.determineConflictWith(subcommand.local_flags);
            if (flag_conflict.has_conflict) {
                return diagnostics.reportAndFail(
                    flag_conflict.diagnostic_type(self.name, subcommand.name),
                );
            }
        }
    }

    /// Executes the command, starting the parsing and execution flow.
    ///
    /// This is an internal entry point, called by `Commands`.
    /// It initializes necessary parsing structures and delegates to `executeInternal`.
    ///
    /// Parameters:
    ///   self: The `Command` instance to execute.
    ///   arguments: A pointer to the `Arguments` iterator.
    ///   diagnostics: A pointer to the `Diagnostics` instance.
    ///   allocator: The allocator to use for internal parsing structures.
    ///
    /// Returns:
    ///   `void` on successful execution, or an error if parsing or execution fails.
    fn execute(self: Command, arguments: *Arguments, diagnostics: *Diagnostics, allocator: std.mem.Allocator) !void {
        var flags = Flags.init(allocator);
        defer flags.deinit();

        var parsed_flags = ParsedFlags.init(allocator);
        defer parsed_flags.deinit();

        return try self.executeInternal(arguments, &flags, &parsed_flags, diagnostics, allocator);
    }

    /// The core recursive execution logic for a command.
    ///
    /// This method handles:
    /// - Merging inherited flags.
    /// - Parsing command-line arguments and flags.
    /// - Validating argument count.
    /// - Executing the command's action (either `executable` or delegating to a subcommand).
    /// - Printing help on error or if requested.
    ///
    /// Parameters:
    ///   self: The `Command` instance to execute.
    ///   arguments: A pointer to the `Arguments` iterator.
    ///   inherited_flags: A pointer to `Flags` inherited from parent commands.
    ///   inherited_parsed_flags: A pointer to `ParsedFlags` inherited from parent commands.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting.
    ///   allocator: The allocator to use for temporary structures.
    ///
    /// Returns:
    ///   `void` on successful execution, or an error if parsing or execution fails.
    fn executeInternal(self: Command, arguments: *Arguments, inherited_flags: *Flags, inherited_parsed_flags: *ParsedFlags, diagnostics: *Diagnostics, allocator: std.mem.Allocator) !void {
        var all_flags = Flags.init(allocator);
        defer all_flags.deinit();

        try self.merge_flags(inherited_flags, &all_flags, true, diagnostics);

        var parsed_flags = ParsedFlags.init(allocator);
        defer parsed_flags.deinit();

        try parsed_flags.mergeFrom(inherited_parsed_flags);

        var parsed_arguments = std.ArrayList([]const u8).init(allocator);
        defer parsed_arguments.deinit();

        var command_line_parser = CommandLineParser.init(arguments, all_flags, diagnostics);
        command_line_parser.parse(&parsed_flags, &parsed_arguments, if (self.action == .executable) false else true) catch |err| {
            diagnostics.log_using(self.output_stream);
            try self.printHelp(&all_flags);
            return err;
        };

        if (parsed_flags.containsHelp()) {
            return try self.printHelp(&all_flags);
        }

        switch (self.action) {
            .executable => |executable_fn| {
                if (self.argument_specification) |argument_specification| {
                    argument_specification.validate(parsed_arguments.items.len, diagnostics) catch |err| {
                        diagnostics.log_using(self.output_stream);
                        try self.printHelp(&all_flags);
                        return err;
                    };
                }

                try all_flags.addFlagsWithDefaultValueTo(&parsed_flags);
                return executable_fn(parsed_flags, parsed_arguments.items);
            },
            .subcommands => |sub_commands| {
                const sub_command = self
                    .get_subcommand(&parsed_arguments, sub_commands, diagnostics) catch |err| {
                    diagnostics.log_using(self.output_stream);
                    try self.printHelp(&all_flags);
                    return err;
                };

                var child_flags = Flags.init(allocator);
                defer child_flags.deinit();

                try self.merge_flags(inherited_flags, &child_flags, false, diagnostics);
                try child_flags.addFlagsWithDefaultValueTo(&parsed_flags);

                return sub_command.executeInternal(arguments, &child_flags, &parsed_flags, diagnostics, allocator);
            },
        }
    }

    /// Merges flags from different sources into a target `Flags` collection.
    ///
    /// This function is used to aggregate local, persistent, and inherited flags
    /// for a command's execution context.
    ///
    /// Parameters:
    ///   self: The `Command` instance whose flags are being merged.
    ///   inherited_flags: A pointer to `Flags` inherited from parent commands.
    ///   target_flags: A pointer to the `Flags` collection where merged flags will be stored.
    ///   should_merge_local_flags: If `true`, `self.local_flags` will be merged.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors during merge.
    ///
    /// Returns:
    ///   `void` on success, or an error if a merge operation fails.
    fn merge_flags(self: Command, inherited_flags: *Flags, target_flags: *Flags, should_merge_local_flags: bool, diagnostics: *Diagnostics) !void {
        if (should_merge_local_flags) {
            try target_flags.mergeFrom(&self.local_flags, diagnostics);
        }
        if (self.persistent_flags) |persistent_flags| {
            try target_flags.mergeFrom(&persistent_flags, diagnostics);
        }
        try target_flags.mergeFrom(inherited_flags, diagnostics);
    }

    /// Retrieves the subcommand to execute based on parsed arguments.
    ///
    /// Parameters:
    ///   self: The parent `Command` instance.
    ///   parsed_arguments: A pointer to the `std.ArrayList` containing parsed positional arguments.
    ///   sub_commands: The `Commands` collection of available subcommands.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   The `Command` struct of the subcommand to execute.
    ///   Returns `CommandParsingError.NoSubcommandProvided` if no subcommand argument is found.
    ///   Returns `CommandParsingError.SubcommandNotAddedToParentCommand` if the subcommand is not found in the collection.
    fn get_subcommand(self: Command, parsed_arguments: *std.ArrayList([]const u8), sub_commands: Commands, diagnostics: *Diagnostics) !Command {
        if (parsed_arguments.items.len == 0) {
            return diagnostics.reportAndFail(.{ .NoSubcommandProvided = .{
                .command = self.name,
            } });
        }
        const subcommand_name = parsed_arguments.pop() orelse
            return diagnostics.reportAndFail(.{ .NoSubcommandProvided = .{
                .command = self.name,
            } });

        const sub_command = sub_commands.get(subcommand_name) orelse
            return diagnostics.reportAndFail(.{ .SubcommandNotAddedToParentCommand = .{
                .command = self.name,
                .subcommand = subcommand_name,
            } });
        return sub_command;
    }

    /// Internal helper to print the help message for this command.
    /// Delegates the actual printing to `CommandHelp`.
    ///
    /// Parameters:
    ///   self: The `Command` instance.
    ///   all_flags: A pointer to the `Flags` collection containing all applicable flags for this command.
    ///
    /// Returns:
    ///   `void` on success, or an error if printing fails.
    fn printHelp(self: Command, all_flags: *Flags) !void {
        const help = CommandHelp.init(self, self.output_stream);
        return try help.printHelp(self.allocator, all_flags);
    }
};

/// Represents a collection of commands, typically used for top-level commands
/// or subcommands within a parent command.
///
/// This struct manages commands by their name and aliases, handles adding
/// new commands, retrieving them, and orchestrating their execution.
pub const Commands = struct {
    /// A hash map storing `Command` structs, keyed by their name.
    command_by_name: std.StringHashMap(Command),
    /// A hash map mapping command aliases to their primary command names.
    command_name_by_alias: std.StringHashMap([]const u8),
    /// The allocator used for managing the memory of the hash maps and the commands they contain.
    allocator: std.mem.Allocator,
    /// The output stream used for printing messages and errors.
    output_stream: OutputStream,

    /// Initializes an empty `Commands` collection.
    ///
    /// Parameters:
    ///   allocator: The allocator to use for the internal hash maps.
    ///   output_stream: The `OutputStream` to use for printing.
    pub fn init(
        allocator: std.mem.Allocator,
        output_stream: OutputStream,
    ) Commands {
        return .{
            .command_by_name = std.StringHashMap(Command).init(allocator),
            .command_name_by_alias = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
            .output_stream = output_stream,
        };
    }

    /// Adds a default "help" command to this collection.
    ///
    /// This help command is a simple executable that does nothing, as its
    /// primary purpose is to trigger the help display logic in `CliCraft`.
    ///
    /// Parameters:
    ///   self: A pointer to the `Commands` instance.
    ///
    /// Returns:
    ///   `void` on success, or an error if the help command cannot be added (e.g., name conflict).
    pub fn addHelp(self: *Commands) !void {
        const runnable = struct {
            pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
                return;
            }
        }.run;

        const command = try Command.init("help", "Displays system help", runnable, self.output_stream, self.allocator);
        try self.command_by_name.put("help", command);
    }

    /// Adds a command to this collection, allowing it to be a child command (i.e., have a parent).
    ///
    /// This is typically used when adding subcommands to a parent command.
    ///
    /// Parameters:
    ///   self: A pointer to the `Commands` instance.
    ///   command: A pointer to the `Command` struct to add. The command will be frozen.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on success, or a `CommandAddError` if a conflict occurs.
    pub fn add_allow_child(self: *Commands, command: *Command, diagnostics: *Diagnostics) !void {
        return try self.add(command, true, diagnostics);
    }

    /// Adds a command to this collection, disallowing it from being a child command.
    ///
    /// This is typically used when adding top-level commands to `CliCraft`.
    ///
    /// Parameters:
    ///   self: A pointer to the `Commands` instance.
    ///   command: A pointer to the `Command` struct to add. The command will be frozen.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on success, or a `CommandAddError` if a conflict occurs or if `command` is already a child.
    pub fn add_disallow_child(self: *Commands, command: *Command, diagnostics: *Diagnostics) !void {
        return try self.add(command, false, diagnostics);
    }

    /// Retrieves a `Command` from the collection by its name or alias.
    ///
    /// Parameters:
    ///   self: The `Commands` instance to query.
    ///   command_name_or_alias: The name or alias of the command to retrieve.
    ///
    /// Returns:
    ///   A `Command` struct if found, or `null` if the command does not exist.
    pub fn get(self: Commands, command_name_or_alias: []const u8) ?Command {
        if (self.command_by_name.get(command_name_or_alias)) |command| {
            return command;
        }
        if (self.command_name_by_alias.get(command_name_or_alias)) |command_name| {
            return self.command_by_name.get(command_name);
        }
        return null;
    }

    /// Executes the appropriate command based on the provided arguments.
    ///
    /// This is the main execution entry point for a collection of commands (e.g., top-level commands).
    /// It identifies the command to execute, handles the special "help" command,
    /// and then delegates execution to the found command.
    ///
    /// Parameters:
    ///   self: The `Commands` instance containing the commands to execute.
    ///   application_description: An optional description for the entire application, used for general help.
    ///   arguments: A pointer to the `Arguments` iterator providing command-line input.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on successful execution, or a `CommandExecutionError` if no command is provided or found.
    pub fn execute(self: Commands, application_description: ?[]const u8, arguments: *Arguments, diagnostics: *Diagnostics) !void {
        const command_name_or_alias = arguments.next() orelse
            return diagnostics.reportAndFail(.{ .MissingCommandNameToExecute = .{} });

        const command = self.get(command_name_or_alias) orelse
            return diagnostics.reportAndFail(.{ .CommandNotFound = .{ .command = command_name_or_alias } });

        if (command.isHelp()) {
            try self.printHelp(application_description);
            return;
        }
        return try command.execute(arguments, diagnostics, self.allocator);
    }

    /// Prints the general help message for the collection of commands.
    ///
    /// This method initializes a `CommandsHelp` instance and delegates the
    /// task of printing the comprehensive help message, which typically includes
    /// the application description, general usage, and a list of all available commands.
    ///
    /// Parameters:
    ///   self: The `Commands` instance for which to print help.
    ///   application_description: An optional string providing a high-level description of the application.
    ///
    /// Returns:
    ///   `void` on successful printing, or an error if an I/O operation fails.
    pub fn printHelp(self: Commands, application_description: ?[]const u8) !void {
        const help = CommandsHelp.init(self, application_description, self.output_stream);
        try help.printHelp(self.allocator);
    }

    /// Deinitializes the `Commands` collection, freeing all associated allocated memory.
    ///
    /// This includes the internal hash maps and all `Command` structs (and their internal data)
    /// stored within `command_by_name`.
    /// This should be called when the `Commands` instance is no longer needed to prevent memory leaks.
    ///
    /// Parameters:
    ///   self: A pointer to the `Commands` instance.
    pub fn deinit(self: *Commands) void {
        var iterator = self.command_by_name.valueIterator();
        while (iterator.next()) |command| {
            command.deinit();
        }
        self.command_name_by_alias.deinit();
        self.command_by_name.deinit();
    }

    /// Prints a formatted table of all commands in this collection to the output stream.
    ///
    /// This is typically used by help generation functions.
    ///
    /// Parameters:
    ///   self: The `Commands` instance to print.
    ///   table: A pointer to a `prettytable.Table` instance to populate.
    ///   allocator: The allocator to use for temporary string formatting within the table.
    ///
    /// Returns:
    ///   `void` on success, or an error if printing fails.
    pub fn print(self: Commands, table: *prettytable.Table, allocator: std.mem.Allocator) !void {
        var column_values = std.ArrayList([]const u8).init(allocator);
        defer {
            for (column_values.items) |column_value| {
                allocator.free(column_value);
            }
            column_values.deinit();
        }

        try self.output_stream.print("Available Commands:\n", .{});
        var iterator = self.command_by_name.iterator();

        var aliases_str: []const u8 = "";
        while (iterator.next()) |entry| {
            const command_name = entry.key_ptr.*;
            const command = entry.value_ptr;

            aliases_str = "";
            if (command.aliases) |aliases| {
                if (aliases.items.len > 0) {
                    var aliases_builder = std.ArrayList(u8).init(allocator);
                    defer aliases_builder.deinit();

                    var first_alias = true;
                    try aliases_builder.writer().writeAll("(");

                    for (aliases.items) |alias| {
                        if (!first_alias) {
                            try aliases_builder.writer().writeAll(", ");
                        }
                        try aliases_builder.writer().print("{s}", .{alias});
                        first_alias = false;
                    }
                    try aliases_builder.writer().writeAll(")");
                    aliases_str = try aliases_builder.toOwnedSlice();

                    try column_values.append(aliases_str);
                }
            }
            try table.addRow(&[_][]const u8{ command_name, aliases_str, command.description });
        }

        try self.output_stream.printTable(table);
    }

    /// Internal helper function to add a command to the collection.
    ///
    /// This function performs core validation checks:
    /// - Prevents adding a child command if `allow_child` is `false`.
    /// - Ensures the command name and its aliases do not conflict with existing commands.
    /// - Freezes the command after successful addition to prevent further modification.
    ///
    /// Parameters:
    ///   self: A pointer to the `Commands` instance.
    ///   command: A pointer to the `Command` struct to add.
    ///   allow_child: If `true`, allows adding commands that have a parent.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on success, or a `CommandAddError` if a validation fails.
    fn add(self: *Commands, command: *Command, allow_child: bool, diagnostics: *Diagnostics) !void {
        if (!allow_child and command.has_parent) {
            return diagnostics.reportAndFail(.{ .ChildCommandAdded = .{ .command = command.name } });
        }

        try self.ensureCommandDoesNotExist(command, diagnostics);

        command.freeze();

        try self.command_by_name.put(command.name, command.*);
        if (command.aliases) |aliases| {
            for (aliases.items) |alias| {
                try self.command_name_by_alias.put(alias, command.name);
            }
        }
    }

    /// Internal helper function to ensure a command (by name and aliases) does not
    /// already exist in this collection.
    ///
    /// This is used by `add` to prevent name and alias conflicts.
    ///
    /// Parameters:
    ///   self: The `Commands` instance to check against.
    ///   command: A pointer to the `Command` to check for existence.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on success (no conflict), or a `CommandAddError` if a conflict is detected.
    fn ensureCommandDoesNotExist(self: Commands, command: *Command, diagnostics: *Diagnostics) !void {
        if (self.command_by_name.contains(command.name)) {
            return diagnostics.reportAndFail(.{ .CommandNameAlreadyExists = .{ .command = command.name } });
        }
        if (command.aliases) |aliases| {
            for (aliases.items) |alias| {
                if (self.command_name_by_alias.get(alias)) |other_command_name| {
                    return diagnostics.reportAndFail(.{ .CommandAliasAlreadyExists = .{
                        .alias = alias,
                        .existing_command = other_command_name,
                    } });
                }
            }
        }
        return;
    }
};

const FlagFactory = @import("flags.zig").FlagFactory;

test "initialize a command with an executable action" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("test", "test command", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try std.testing.expectEqualStrings("test", command.name);
    try std.testing.expectEqualStrings("test command", command.description);
}

test "initialize a command with a local flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    const verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build();

    var command = try Command.init("test", "test command", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(verbose_flag);

    defer command.deinit();

    try std.testing.expectEqualStrings("verbose", command.local_flags.get("verbose").?.name);
}

test "initialize a command without any flags" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("test", "test command", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try std.testing.expect(command.local_flags.get("help") != null);
}

test "initialize an executable command with an alias" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setAliases(&[_]CommandAlias{"str"});

    defer command.deinit();

    try std.testing.expect(command.aliases != null);

    const aliases = command.aliases.?;

    try std.testing.expectEqual(aliases.items.len, 1);
    try std.testing.expectEqualStrings("str", aliases.items[0]);
}

test "initialize an executable command with a couple of aliases" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setAliases(&[_]CommandAlias{ "str", "strm" });

    defer command.deinit();

    try std.testing.expect(command.aliases != null);

    const aliases = command.aliases.?;

    try std.testing.expectEqual(aliases.items.len, 2);
    try std.testing.expectEqualStrings("str", aliases.items[0]);
    try std.testing.expectEqualStrings("strm", aliases.items[1]);
}

test "freeze a subcommand after adding it to a parent command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(kubectl_command.action.subcommands.get("get") != null);
    try std.testing.expect(get_command.frozen);
}

test "attempt to set argument specification to frozen command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(get_command.frozen);
    try std.testing.expectError(CommandMutationError.CommandAlreadyFrozen, get_command.setArgumentSpecification(ArgumentSpecification.mustBeExact(2)));
}

test "attempt to set usage on frozen command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(get_command.frozen);
    try std.testing.expectError(CommandMutationError.CommandAlreadyFrozen, get_command.setUsage("get <object type>"));
}

test "attempt to add flag to frozen command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(get_command.frozen);
    var verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "define verbose output",
        FlagType.boolean,
    ).build();

    defer verbose_flag.deinit();
    try std.testing.expectError(CommandMutationError.CommandAlreadyFrozen, get_command.addFlag(verbose_flag));
}

test "attempt to add aliases to frozen command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(get_command.frozen);
    try std.testing.expectError(CommandMutationError.CommandAlreadyFrozen, get_command.setAliases(&[_]CommandAlias{ "str", "strm" }));
}

test "initialize a parent command with subcommands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    try std.testing.expect(kubectl_command.action.subcommands.get("get") != null);
    try std.testing.expectEqualStrings("get", kubectl_command.action.subcommands.get("get").?.name);
}

test "attempt to add a subcommand with same flag short name as the parent's persistent short flag but with different long name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Define priority",
        FlagType.boolean,
    ).withShortName('v').markPersistent().build());
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Define verbose output",
        FlagType.boolean,
    ).withShortName('v').build());
    defer get_command.deinit();

    try std.testing.expectError(FlagErrors.FlagConflictDetected, kubectl_command.addSubcommand(&get_command));
}

test "attempt to add a subcommand with same flag as the parent's persistent flag but without short name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Define verbose output",
        FlagType.boolean,
    ).withShortName('v').markPersistent().build());
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Define verbose output",
        FlagType.boolean,
    ).build());
    defer get_command.deinit();

    try std.testing.expectError(FlagErrors.FlagConflictDetected, kubectl_command.addSubcommand(&get_command));
}

test "initialize an executable command with argument specification (1)" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setArgumentSpecification(ArgumentSpecification.mustBeMinimum(1));

    defer command.deinit();

    try std.testing.expect(command.argument_specification != null);
    try std.testing.expectEqual(ArgumentSpecification.mustBeMinimum(1), command.argument_specification.?);
}

test "initialize an executable command with argument specification (2)" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setArgumentSpecification(try ArgumentSpecification.mustBeInEndInclusiveRange(1, 5));

    defer command.deinit();

    try std.testing.expect(command.argument_specification != null);
    try std.testing.expectEqual(ArgumentSpecification.mustBeInEndInclusiveRange(1, 5), command.argument_specification.?);
}

test "initialize an executable command with usage" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setUsage("stringer <string>");

    defer command.deinit();

    try std.testing.expect(command.usage != null);
    try std.testing.expectEqualStrings("stringer <string>", command.usage.?);
}

test "is help command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("help", "prints help", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try std.testing.expect(command.isHelp());
}

test "is not a help command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("HELP", "prints help", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try std.testing.expect(command.isHelp() == false);
}

var add_command_result: u8 = undefined;
var get_command_result: []const u8 = undefined;
var add_command_result_via_flags: i64 = undefined;

test "execute a command with an executable command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            add_command_result = augend + addend;
            return;
        }
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try command.execute(&arguments, &diagnostics, std.testing.allocator);

    try std.testing.expectEqual(7, add_command_result);
}

test "execute a command with a subcommand" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            get_command_result = arguments[0];
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);

    try std.testing.expectEqualStrings("pods", get_command_result);
}

test "execute help for the parent command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", output_stream, std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--help", "get", "pods" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "kubectl").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "get").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "-h").? > 0);
}

test "execute help for the child command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, output_stream, std.testing.allocator);

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "--help", "pods" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "get").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
}

test "attempt to execute a command with a subcommand but with incorrect subcommand name from the argument" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entry", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "delete" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(CommandParsingError.SubcommandNotAddedToParentCommand, kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator));
}

test "attempt to execute a command with an unregistered flag and it should print command's help" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const ouptut_stream = OutputStream.initStdErrWriter(writer.any());

    var command = try Command.init("add", "add numbers", runnable, ouptut_stream, std.testing.allocator);
    defer command.deinit();

    var diagnostics: Diagnostics = .{};

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "4", "--verbose" });
    arguments.skipFirst();

    command.execute(&arguments, &diagnostics, std.testing.allocator) catch {};

    const diagnostics_type = diagnostics.diagnostics_type.?.FlagNotFound;
    try std.testing.expectEqualStrings("verbose", diagnostics_type.flag_name);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "add").? >= 0);
}

test "attempt to execute a command with invalid argument specification and it should print command's help" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const ouptut_stream = OutputStream.initStdErrWriter(writer.any());

    var command = try Command.init("add", "add numbers", runnable, ouptut_stream, std.testing.allocator);
    try command.setArgumentSpecification(ArgumentSpecification.mustBeExact(2));
    defer command.deinit();

    var diagnostics: Diagnostics = .{};

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "4", "5" });
    arguments.skipFirst();

    command.execute(&arguments, &diagnostics, std.testing.allocator) catch {};

    try std.testing.expectEqual(3, diagnostics.diagnostics_type.?.ArgumentsNotMatchingExpected.actual_arguments);
    try std.testing.expectEqual(2, diagnostics.diagnostics_type.?.ArgumentsNotMatchingExpected.expected_arguments);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "add").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "accepts exactly 2 argument(s)").? > 0);
}

test "attempt to execute a command with incorrect child command and it should print command's help" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const ouptut_stream = OutputStream.initStdErrWriter(writer.any());

    var kubectl_command = try Command.initParent("kubectl", "Kubernetes entrypoint", ouptut_stream, std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    try kubectl_command.addSubcommand(&get_command);

    var diagnostics: Diagnostics = .{};

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "delete", "pods" });
    arguments.skipFirst();

    kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator) catch {};

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "kubectl").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "get").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Get objects").? > 0);
}

test "add a local flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).build());
    defer command.deinit();

    try std.testing.expectEqualStrings("priority", command.local_flags.get("priority").?.name);
}

test "attempt to add an existing local flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).build());

    defer command.deinit();

    var duplicate_flag = try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).build();

    defer duplicate_flag.deinit();
    try std.testing.expectError(FlagErrors.FlagNameAlreadyExists, command.addFlag(duplicate_flag));
}

test "attempt to add a local flag which exists as persistent flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer command.deinit();

    try command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).markPersistent().build());

    var duplicate_flag = try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).build();

    defer duplicate_flag.deinit();
    try std.testing.expectError(FlagErrors.FlagNameAlreadyExists, command.addFlag(duplicate_flag));
}

test "add a persistent flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).markPersistent().build());
    defer command.deinit();

    try std.testing.expectEqualStrings("priority", command.persistent_flags.?.get("priority").?.name);
}

test "attempt to add an existing persistent flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).markPersistent().build());

    defer command.deinit();

    var duplicate_flag = try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).markPersistent().build();

    defer duplicate_flag.deinit();
    try std.testing.expectError(FlagErrors.FlagNameAlreadyExists, command.addFlag(duplicate_flag));
}

test "attempt to add a persistent flag which exists as local flag" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {}
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).build());

    defer command.deinit();

    var duplicate_flag = try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).markPersistent().build();

    defer duplicate_flag.deinit();
    try std.testing.expectError(FlagErrors.FlagNameAlreadyExists, command.addFlag(duplicate_flag));
}

test "print command aliases" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initStdErrWriter(writer.any()), std.testing.allocator);
    try command.setAliases(&[_]CommandAlias{ "str", "strm" });

    defer command.deinit();

    try std.testing.expect(command.aliases != null);

    var table = prettytable.Table.init(std.testing.allocator);
    defer table.deinit();

    table.setFormat(prettytable.FORMAT_CLEAN);
    try command.printAliases(&table);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "str").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "strm").? > 0);
}

test "execute a command passing flags and arguments" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            try std.testing.expect(try flags.getBoolean("verbose"));
            try std.testing.expect(try flags.getBoolean("priority"));
            try std.testing.expectEqual(23, try flags.getInt64("timeout"));

            add_command_result = augend + addend;
            return;
        }
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build());

    try command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).build());

    try command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "timeout",
        "Define timeout",
        FlagValue.type_int64(25),
    ).withShortName('t').build());

    defer command.deinit();

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "-t", "23", "2", "5", "--verbose", "--priority" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try command.execute(&arguments, &diagnostics, std.testing.allocator);
    try std.testing.expectEqual(7, add_command_result);
}

test "execute a command with child command passing flags and arguments 1" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose"));

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define namespace",
        FlagType.string,
    ).markPersistent().build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "--verbose", "pods" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments 2" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define namespace",
        FlagType.string,
    ).markPersistent().build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments with a persistent flag having default value" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);
            try std.testing.expectEqual(100, try flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define namespace",
        FlagType.string,
    ).markPersistent().build());

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "priority",
        "Define priority",
        FlagValue.type_int64(100),
    ).markPersistent().build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments with a local flag having default value 1" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);
            try std.testing.expectError(FlagErrors.FlagNotFound, flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define namespace",
        FlagType.string,
    ).markPersistent().build());

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "priority",
        "Define priority",
        FlagValue.type_int64(100),
    ).build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments with a local flag having default value 2" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);
            try std.testing.expectEqual(20, try flags.getInt64("timeout"));
            try std.testing.expectError(FlagErrors.FlagNotFound, flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define namespace",
        FlagType.string,
    ).markPersistent().build());

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "timeout",
        "Define timeout",
        FlagValue.type_int64(20),
    ).markPersistent().build());

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "priority",
        "Define priority",
        FlagValue.type_int64(100),
    ).build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing flags and arguments with a local flag having default value 3" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqualStrings("cli-craft", try flags.getString("namespace"));
            try std.testing.expect(try flags.getBoolean("verbose") == false);
            try std.testing.expectEqual(40, try flags.getInt64("timeout"));
            try std.testing.expectError(FlagErrors.FlagNotFound, flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try get_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build());

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define namespace",
        FlagType.string,
    ).markPersistent().build());

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "timeout",
        "Define timeout",
        FlagValue.type_int64(20),
    ).markPersistent().build());

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "priority",
        "Define priority",
        FlagValue.type_int64(100),
    ).build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--namespace", "cli-craft", "--timeout", "40", "get", "pods", "--verbose", "false" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing a local flag which is also inherited from parent" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqual(50, try flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();
    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "priority",
        "Enable priority",
        FlagType.int64,
    ).markPersistent().build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "--priority", "20", "get", "pods", "--priority", "50" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command passing a local flag which is also inherited from parent with default value" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqual(75, try flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();
    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "priority",
        "Enable priority",
        FlagValue.type_int64(100),
    ).markPersistent().build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods", "--priority", "75" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

test "execute a command with child command with a inherited flag from parent with default value" {
    const runnable = struct {
        pub fn run(flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const argument = arguments[0];

            try std.testing.expectEqualStrings("pods", argument);
            try std.testing.expectEqual(100, try flags.getInt64("priority"));

            return;
        }
    }.run;

    var get_command = try Command.init("get", "Get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var kubectl_command = try Command.initParent("kubectl", "Entry point", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    try kubectl_command.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "priority",
        "Enable priority",
        FlagValue.type_int64(100),
    ).markPersistent().build());

    try kubectl_command.addSubcommand(&get_command);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods" });
    arguments.skipFirst();

    var diagnostics: Diagnostics = .{};
    try kubectl_command.execute(&arguments, &diagnostics, std.testing.allocator);
}

const ArgumentSpecification = @import("argument-specification.zig").ArgumentSpecification;
const ArgumentSpecificationError = @import("argument-specification.zig").ArgumentValidationError;

test "attempt to add a command which has a parent" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer kubectl_command.deinit();

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(CommandAddError.ChildCommandAdded, commands.add_disallow_child(&get_command, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.ChildCommandAdded;
    try std.testing.expectEqualStrings("get", diagnostics_type.command);
}

test "add a command which has a child" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&kubectl_command, &diagnostics);

    const retrieved = commands.get("kubectl");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("kubectl", retrieved.?.name);
}

test "add a command and freeze it post add" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);

    const retrieved = commands.get("stringer");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("stringer", retrieved.?.name);
    try std.testing.expect(command.frozen);
}

test "add a command with a name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);

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

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setAliases(&[_]CommandAlias{"str"});

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);

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

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setAliases(&[_]CommandAlias{ "str", "strm" });

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);

    try std.testing.expectEqualStrings("stringer", commands.get("str").?.name);
    try std.testing.expectEqualStrings("stringer", commands.get("strm").?.name);
}

test "print commands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setAliases(&[_]CommandAlias{ "str", "strm" });

    var add_command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try add_command.setAliases(&[_]CommandAlias{"sum"});

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();

    var commands = Commands.init(std.testing.allocator, OutputStream.initStdErrWriter(writer.any()));
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);
    try commands.add_disallow_child(&add_command, &diagnostics);

    var table = prettytable.Table.init(std.testing.allocator);
    defer table.deinit();

    table.setFormat(prettytable.FORMAT_CLEAN);

    try commands.print(&table, std.testing.allocator);
    const value = buffer.items;

    try std.testing.expect(std.mem.indexOf(u8, value, "stringer").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "str").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "strm").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "sum").? > 0);
}

test "attempt to add a command with an existing name" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    var diagnostics: Diagnostics = .{};

    try commands.add_disallow_child(&command, &diagnostics);

    var another_command = try Command.init("stringer", "manipulate strings with a blazing fast speed", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    defer another_command.deinit();

    try std.testing.expectError(CommandAddError.CommandNameAlreadyExists, commands.add_disallow_child(&another_command, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.CommandNameAlreadyExists;
    try std.testing.expectEqualStrings("stringer", diagnostics_type.command);
}

test "attempt to add a command with an existing alias" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var command = try Command.init("stringer", "manipulate strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setAliases(&[_]CommandAlias{"str"});

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);

    var another_command = try Command.init("fast string", "manipulate strings with a blazing fast speed", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try another_command.setAliases(&[_]CommandAlias{"str"});
    defer another_command.deinit();

    try std.testing.expectError(CommandAddError.CommandAliasAlreadyExists, commands.add_disallow_child(&another_command, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.CommandAliasAlreadyExists;
    try std.testing.expectEqualStrings("str", diagnostics_type.alias);
    try std.testing.expectEqualStrings("stringer", diagnostics_type.existing_command);
}

test "execute a command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            add_command_result = augend + addend;
            return;
        }
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5" });
    try commands.execute(null, &arguments, &diagnostics);

    try std.testing.expectEqual(7, add_command_result);
}

test "execute help command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var add_command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try add_command.setAliases(&[_][]const u8{"plus"});

    var subtract_command = try Command.init("sub", "subtract numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try subtract_command.setAliases(&[_][]const u8{"minus"});

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var commands = Commands.init(std.testing.allocator, output_stream);
    defer commands.deinit();

    try commands.addHelp();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&add_command, &diagnostics);
    try commands.add_disallow_child(&subtract_command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{"help"});
    try commands.execute("maths application", &arguments, &diagnostics);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "maths application").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "add").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "plus").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "sub").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "minus").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "-h").? > 0);
}

test "execute a command with a subcommand by adding the parent command" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            get_command_result = arguments[0];
            return;
        }
    }.run;

    var kubectl_command = try Command.initParent("kubectl", "kubernetes entrypoint", OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    var get_command = try Command.init("get", "get objects", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try kubectl_command.addSubcommand(&get_command);

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&kubectl_command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods" });
    try commands.execute(null, &arguments, &diagnostics);

    try std.testing.expectEqualStrings("pods", get_command_result);
}

test "attempt to execute a command with an unregistered command from command line" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setArgumentSpecification(ArgumentSpecification.mustBeMaximum(3));

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "subtract", "2", "4" });
    try std.testing.expectError(CommandExecutionError.CommandNotFound, commands.execute(null, &arguments, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.CommandNotFound;
    try std.testing.expectEqualStrings("subtract", diagnostics_type.command);
}

test "attempt to execute a command with mismatch in argument specification" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.init("add", "add numbers", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try command.setArgumentSpecification(ArgumentSpecification.mustBeMaximum(3));

    var commands = Commands.init(std.testing.allocator, OutputStream.initNoOperationOutputStream());
    defer commands.deinit();

    var diagnostics: Diagnostics = .{};
    try commands.add_disallow_child(&command, &diagnostics);

    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5", "6", "3" });
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsGreaterThanMaximum, commands.execute(null, &arguments, &diagnostics));
}
