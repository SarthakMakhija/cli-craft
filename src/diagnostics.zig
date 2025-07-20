const std = @import("std");
const FlagType = @import("flags.zig").FlagType;
const FlagErrors = @import("flags.zig").FlagErrors;
const CommandErrors = @import("commands.zig").CommandErrors;
const ArgumentValidationError = @import("argument-specification.zig").ArgumentValidationError;
const ArgumentSpecificationError = @import("argument-specification.zig").ArgumentSpecificationError;

const OutputStream = @import("stream.zig").OutputStream;

/// A struct for collecting and reporting diagnostic messages and errors encountered
/// during the parsing, validation, and execution of CLI commands and flags.
///
/// It stores the type of diagnostic and provides methods to log it to an `OutputStream`
/// and to convert it into a corresponding error.
pub const Diagnostics = struct {
    /// The specific type of diagnostic message, containing context-relevant data.
    diagnostics_type: ?DiagnosticType = null,

    /// Logs the stored diagnostic message to the provided `OutputStream`.
    ///
    /// This function formats the error message based on the `DiagnosticType`
    /// and prints it to the error writer of the `OutputStream`.
    ///
    /// Parameters:
    ///   output_stream: The `OutputStream` to which the diagnostic message will be logged.
    pub fn log_using(self: Diagnostics, output_stream: OutputStream) void {
        if (self.diagnostics_type) |diagnostics_type| switch (diagnostics_type) {
            .FlagNameAlreadyExists => |context| {
                output_stream.printError("Error: Flag name '{s}' already exists.\n\n", .{context.flag_name}) catch {};
            },
            .FlagShortNameAlreadyExists => |context| {
                output_stream.printError("Error: Flag short name '{c}' already exists for flag '{s}'.\n\n", .{ context.short_name, context.existing_flag_name }) catch {};
            },
            .FlagShortNameMergeConflict => |context| {
                output_stream.printError("Error: Flag merge conflict: short name '{c}' for flag '{s}' conflicts with existing flag '{s}'. This is an ambiguous CLI definition.\n\n", .{ context.short_name, context.flag_name, context.conflicting_flag_name }) catch {};
            },
            .FlagConflictSameLongNameDifferentShortName => |context| {
                output_stream.printError("Error: Flag conflict: Command '{s}' subcommand '{s}' has flag '{s}' with short name '{c}', which conflicts with another short name '{c}' for the same long name.\n\n", .{ context.command, context.subcommand, context.flag_name, context.short_name, context.other_short_name }) catch {};
            },
            .FlagConflictSameShortNameDifferentLongName => |context| {
                output_stream.printError("Error: Flag conflict: Command '{s}' subcommand '{s}' has flag '{s}' and flag '{s}' both using short name '{c}'.\n\n", .{ context.command, context.subcommand, context.flag_name, context.other_flag_name, context.short_name }) catch {};
            },
            .FlagConflictMissingShortName => |context| {
                output_stream.printError("Error: Flag conflict: Command '{s}' subcommand '{s}' has flag '{s}' missing expected short name '{c}'.\n\n", .{ context.command, context.subcommand, context.flag_name, context.expected_short_name }) catch {};
            },
            .InvalidBoolean => |context| {
                output_stream.printError("Error: Invalid boolean value '{s}' for flag '{s}'. Expected 'true' or 'false'.\n\n", .{ context.value, context.flag_name }) catch {};
            },
            .InvalidInteger => |context| {
                output_stream.printError("Error: Invalid integer value '{s}' for flag '{s}'. Expected a number.\n\n", .{ context.value, context.flag_name }) catch {};
            },
            .FlagNotFound => |context| {
                output_stream.printError("Error: Flag '{s}' not found.\n\n", .{context.flag_name}) catch {};
            },
            .FlagTypeMismatch => |context| {
                output_stream.printError("Error: Type mismatch for flag '{s}'. Expected {s}, but value provided was '{s}'.\n\n", .{ context.flag_name, @tagName(context.expected_type), context.value }) catch {};
            },
            .NoFlagsAddedToCommand => |context| {
                output_stream.printError("Error: No flags added to the command but found the flag '{s}'.\n\n", .{context.parsed_flag}) catch {};
            },
            .NoFlagValueProvided => |context| {
                output_stream.printError("Error: No flag value provided for flag '{s}'.\n\n", .{context.parsed_flag}) catch {};
            },
            .NoSubcommandProvided => |context| {
                output_stream.printError("Error: No subcommand provided for command '{s}'.\n\n", .{context.command}) catch {};
            },
            .SubcommandNotAddedToParentCommand => |context| {
                output_stream.printError("Error: Subcommand '{s}' not added to the parent command '{s}'.\n\n", .{ context.subcommand, context.command }) catch {};
            },
            .SubCommandNameSameAsParent => |context| {
                output_stream.printError("Error: Subcommand name '{s}' is same as the parent command name.\n\n", .{context.command}) catch {};
            },
            .SubCommandAddedToExecutable => |context| {
                output_stream.printError("Error: Subcommand '{s}' added to an executable command '{s}'.\n\n", .{ context.command, context.subcommand }) catch {};
            },
            .ChildCommandAdded => |context| {
                output_stream.printError("Error: Child command '{s}' added to Cli-Craft.\n\n", .{context.command}) catch {};
            },
            .CommandNameAlreadyExists => |context| {
                output_stream.printError("Error: Command name '{s}' already exists.\n\n", .{context.command}) catch {};
            },
            .CommandAliasAlreadyExists => |context| {
                output_stream.printError("Error: Command alias '{s}' already exists for command '{s}'.\n\n", .{ context.alias, context.existing_command }) catch {};
            },
            .MissingCommandNameToExecute => |_| {
                output_stream.printError("Error: No command provided to execute.\n\n", .{}) catch {};
            },
            .CommandNotFound => |context| {
                output_stream.printError("Error: Command '{s}' not found.\n\n", .{context.command}) catch {};
            },
            .CommandAlreadyFrozen => |context| {
                output_stream.printError("Error: Command '{s}' is frozen and cannot be modified after being added as a subcommand or to the top-level CLI.\n\n", .{context.command}) catch {};
            },
            .ArgumentsNotEqualToZero => |context| {
                output_stream.printError("Error: Expected zero arguments, received {d}.\n\n", .{context.actual_arguments}) catch {};
            },
            .ArgumentsLessThanMinimum => |context| {
                output_stream.printError("Error: Expected a minimum of {d} argument(s), received {d}.\n\n", .{ context.expected_arguments, context.actual_arguments }) catch {};
            },
            .ArgumentsGreaterThanMaximum => |context| {
                output_stream.printError("Error: Expected a maximum of {d} argument(s), received {d}.\n\n", .{ context.expected_arguments, context.actual_arguments }) catch {};
            },
            .ArgumentsNotMatchingExpected => |context| {
                output_stream.printError("Error: Expected {d} argument(s), received {d}.\n\n", .{ context.expected_arguments, context.actual_arguments }) catch {};
            },
            .ArgumentsNotInEndExclusiveRange => |context| {
                output_stream.printError("Error: Expected between {d} and {d} (exclusive) arguments, but received {d}.\n\n", .{ context.minimum_arguments, context.maximum_arguments, context.actual_arguments }) catch {};
            },
            .ArgumentsNotInEndInclusiveRange => |context| {
                output_stream.printError("Error: Expected between {d} and {d} (inclusive) arguments, but received {d}.\n\n", .{ context.minimum_arguments, context.maximum_arguments, context.actual_arguments }) catch {};
            },
            .ExecutionError => |context| {
                output_stream.printError("Error: Command '{s}' execution failed: {any}.\n\n", .{ context.command, context.err }) catch {};
            },
        };
    }

    /// Reports a diagnostic message and returns the corresponding error.
    ///
    /// This function sets the internal `diagnostics_type` and then returns
    /// the appropriate error from the `FlagErrors`, `CommandErrors`, or `ArgumentValidationError` sets.
    /// This is typically used in conjunction with the `?` operator or `catch` block
    /// to propagate errors after logging.
    ///
    /// Parameters:
    ///   diagnostic_type: The specific `DiagnosticType` to report.
    ///
    /// Returns:
    ///   An `anyerror` that corresponds to the provided `diagnostic_type`.
    pub fn reportAndFail(self: *Diagnostics, diagnostic_type: DiagnosticType) anyerror {
        self.diagnostics_type = diagnostic_type;
        return switch (diagnostic_type) {
            .FlagNameAlreadyExists => FlagErrors.FlagNameAlreadyExists,
            .FlagShortNameAlreadyExists => FlagErrors.FlagShortNameAlreadyExists,
            .FlagShortNameMergeConflict => FlagErrors.FlagShortNameMergeConflict,
            .FlagConflictSameLongNameDifferentShortName => FlagErrors.FlagConflictDetected,
            .FlagConflictSameShortNameDifferentLongName => FlagErrors.FlagConflictDetected,
            .FlagConflictMissingShortName => FlagErrors.FlagConflictDetected,
            .InvalidBoolean => FlagErrors.InvalidBoolean,
            .InvalidInteger => FlagErrors.InvalidInteger,
            .FlagNotFound => FlagErrors.FlagNotFound,
            .FlagTypeMismatch => FlagErrors.FlagTypeMismatch,
            .NoFlagsAddedToCommand => CommandErrors.NoFlagsAddedToCommand,
            .NoFlagValueProvided => CommandErrors.NoFlagValueProvided,
            .NoSubcommandProvided => CommandErrors.NoSubcommandProvided,
            .SubcommandNotAddedToParentCommand => CommandErrors.SubcommandNotAddedToParentCommand,
            .SubCommandNameSameAsParent => CommandErrors.SubCommandNameSameAsParent,
            .SubCommandAddedToExecutable => CommandErrors.SubCommandAddedToExecutable,
            .ChildCommandAdded => CommandErrors.ChildCommandAdded,
            .CommandNameAlreadyExists => CommandErrors.CommandNameAlreadyExists,
            .CommandAliasAlreadyExists => CommandErrors.CommandAliasAlreadyExists,
            .MissingCommandNameToExecute => CommandErrors.MissingCommandNameToExecute,
            .CommandNotFound => CommandErrors.CommandNotFound,
            .CommandAlreadyFrozen => CommandErrors.CommandAlreadyFrozen,
            .ArgumentsNotEqualToZero => ArgumentValidationError.ArgumentsNotEqualToZero,
            .ArgumentsLessThanMinimum => ArgumentValidationError.ArgumentsLessThanMinimum,
            .ArgumentsGreaterThanMaximum => ArgumentValidationError.ArgumentsGreaterThanMaximum,
            .ArgumentsNotMatchingExpected => ArgumentValidationError.ArgumentsNotMatchingExpected,
            .ArgumentsNotInEndExclusiveRange => ArgumentValidationError.ArgumentsNotInEndExclusiveRange,
            .ArgumentsNotInEndInclusiveRange => ArgumentValidationError.ArgumentsNotInEndInclusiveRange,
            .ExecutionError => CommandErrors.RunnableExecutionFailed,
        };
    }
};

/// A union representing the specific type of a diagnostic message,
/// carrying relevant context for error reporting.
pub const DiagnosticType = union(enum) {
    /// Indicates that a flag name already exists.
    FlagNameAlreadyExists: struct {
        flag_name: []const u8,
    },
    /// Indicates that a flag short name already exists for another flag.
    FlagShortNameAlreadyExists: struct {
        short_name: u8,
        existing_flag_name: []const u8,
    },
    /// Indicates a conflict during flag merging due to a short name collision.
    FlagShortNameMergeConflict: struct {
        short_name: u8,
        flag_name: []const u8,
        conflicting_flag_name: []const u8,
    },
    /// Indicates a flag conflict where long names are the same but short names differ.
    FlagConflictSameLongNameDifferentShortName: struct {
        command: []const u8,
        subcommand: []const u8,
        flag_name: []const u8,
        short_name: u8,
        other_short_name: u8,
    },
    /// Indicates a flag conflict where short names are the same but long names differ.
    FlagConflictSameShortNameDifferentLongName: struct {
        command: []const u8,
        subcommand: []const u8,
        flag_name: []const u8,
        other_flag_name: []const u8,
        short_name: u8,
    },
    /// Indicates a flag conflict where a short name is missing when expected.
    FlagConflictMissingShortName: struct {
        command: []const u8,
        subcommand: []const u8,
        flag_name: []const u8,
        expected_short_name: u8,
    },
    /// Indicates an invalid boolean value provided for a flag.
    InvalidBoolean: struct {
        flag_name: []const u8,
        value: []const u8,
    },
    /// Indicates an invalid integer value provided for a flag.
    InvalidInteger: struct {
        flag_name: []const u8,
        value: []const u8,
    },
    /// Indicates that a specified flag was not found.
    FlagNotFound: struct {
        flag_name: []const u8,
    },
    /// Indicates a type mismatch when retrieving a flag's value.
    FlagTypeMismatch: struct {
        flag_name: []const u8,
        expected_type: FlagType,
        value: []const u8,
    },
    /// Indicates that no flags were added to a command, but a flag was expected.
    NoFlagsAddedToCommand: struct {
        parsed_flag: []const u8,
    },
    /// Indicates that a flag was provided but no value was given.
    NoFlagValueProvided: struct {
        parsed_flag: []const u8,
    },
    /// Indicates that a subcommand was expected but not provided.
    NoSubcommandProvided: struct {
        command: []const u8,
    },
    /// Indicates that a subcommand was not added to its intended parent command.
    SubcommandNotAddedToParentCommand: struct {
        command: []const u8,
        subcommand: []const u8,
    },
    /// Indicates that a subcommand's name is identical to its parent command's name.
    SubCommandNameSameAsParent: struct {
        command: []const u8,
    },
    /// Indicates an attempt to add a subcommand to an executable command.
    SubCommandAddedToExecutable: struct {
        command: []const u8,
        subcommand: []const u8,
    },
    /// Indicates an attempt to add a child command directly to the top-level `CliCraft` instance.
    ChildCommandAdded: struct {
        command: []const u8,
    },
    /// Indicates that a command name already exists.
    CommandNameAlreadyExists: struct {
        command: []const u8,
    },
    /// Indicates that a command alias already exists for another command.
    CommandAliasAlreadyExists: struct {
        alias: []const u8,
        existing_command: []const u8,
    },
    /// Indicates that no command name was provided for execution.
    MissingCommandNameToExecute: struct {},
    /// Indicates that a specified command was not found.
    CommandNotFound: struct {
        command: []const u8,
    },
    /// Indicates an attempt to modify a command after it has been "frozen" (added to the CLI structure or
    /// subcommand added to parent command).
    CommandAlreadyFrozen: struct {
        command: []const u8,
    },
    /// Indicates that arguments were provided when zero were expected.
    ArgumentsNotEqualToZero: struct {
        actual_arguments: usize,
    },
    /// Indicates that the number of arguments is less than the specified minimum.
    ArgumentsLessThanMinimum: struct {
        actual_arguments: usize,
        expected_arguments: usize,
    },
    /// Indicates that the number of arguments is greater than the specified maximum.
    ArgumentsGreaterThanMaximum: struct {
        actual_arguments: usize,
        expected_arguments: usize,
    },
    /// Indicates that the number of arguments does not exactly match the expected count.
    ArgumentsNotMatchingExpected: struct {
        actual_arguments: usize,
        expected_arguments: usize,
    },
    /// Indicates that the number of arguments falls outside an exclusive range.
    ArgumentsNotInEndExclusiveRange: struct {
        actual_arguments: usize,
        minimum_arguments: usize,
        maximum_arguments: usize,
    },
    /// Indicates that the number of arguments falls outside an inclusive range.
    ArgumentsNotInEndInclusiveRange: struct {
        actual_arguments: usize,
        minimum_arguments: usize,
        maximum_arguments: usize,
    },
    /// Indicates an error during execution of a command.
    ExecutionError: struct {
        command: []const u8,
        err: anyerror,
    },
};
