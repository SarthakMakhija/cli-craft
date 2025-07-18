/// This module provides the core `CliCraft` framework for building declarative
/// command-line applications in Zig. It offers a structured way to define
/// commands, subcommands, flags, and arguments, along with built-in help
/// generation and error handling.
const std = @import("std");

// --- Re-exported Public API Structs ---

/// Represents a single command in the CLI application, which can be either executable or a parent for subcommands.
pub const Command = @import("commands.zig").Command;
/// Type alias for a command's executable function.
pub const CommandFn = @import("commands.zig").CommandFn;
/// Type alias for the arguments passed to a command's executable function.
pub const CommandFnArguments = @import("commands.zig").CommandFnArguments;
/// Represents an alias for a command's name.
pub const CommandAlias = @import("commands.zig").CommandAlias;
/// A list of aliases for a command.
pub const CommandAliases = @import("commands.zig").CommandAliases;

/// Defines the rules for a command's positional arguments.
/// This union allows specifying various constraints on the number of arguments a command expects.
pub const ArgumentSpecification = @import("argument-specification.zig");

/// Represents a single command-line flag, defining its name, type, description, and optional default value.
pub const Flag = @import("flags.zig").Flag;
/// Defines the data type of a flag's value (boolean, int64, or string).
pub const FlagType = @import("flags.zig").FlagType;
/// A union type holding the actual value of a flag, corresponding to its `FlagType`.
pub const FlagValue = @import("flags.zig").FlagValue;

/// A collection of flags that have been parsed from the command line.
/// Provides methods to access parsed flag values.
pub const ParsedFlags = @import("flags.zig").ParsedFlags;
/// Represents a single flag that has been parsed, containing its name and value.
pub const ParsedFlag = @import("flags.zig").ParsedFlag;

/// Errors that can occur during command definition.
pub const CommandAddError = @import("commands.zig").CommandAddError;
/// Errors that can occur during command execution.
pub const CommandExecutionError = @import("commands.zig").CommandExecutionError;
/// Errors related to mutating command properties.
pub const CommandMutationError = @import("commands.zig").CommandMutationError;
/// Errors that can occur during command-line parsing.
pub const CommandParsingError = @import("command-line-parser.zig").CommandParsingError;
/// A comprehensive error type for all command-related operations.
pub const CommandErrors = @import("commands.zig").CommandErrors;

/// Errors that can occur when adding flags.
pub const FlagAddError = @import("flags.zig").FlagAddError;
/// Errors that can occur when retrieving a flag's value with an incorrect type.
pub const FlagValueGetError = @import("flags.zig").FlagValueGetError;
/// Errors that can occur during flag value conversion (e.g., string to int).
pub const FlagValueConversionError = @import("flags.zig").FlagValueConversionError;
/// A comprehensive error type for all flag-related operations.
pub const FlagErrors = @import("flags.zig").FlagErrors;

/// Errors related to argument parsing and validation.
pub const ArgumentsError = @import("arguments.zig").ArgumentsError;

/// A utility for collecting and reporting diagnostic messages and errors.
pub const Diagnostics = @import("diagnostics.zig").Diagnostics;

//Internal Imports

const Commands = @import("commands.zig").Commands;
const Arguments = @import("arguments.zig").Arguments;

const OutputStream = @import("stream.zig").OutputStream;
const FlagFactory = @import("flags.zig").FlagFactory;
const FlagBuilder = @import("flags.zig").FlagBuilder;

/// Global configuration options for the `CliCraft` application.
pub const GlobalOptions = struct {
    /// An optional description for the entire application, displayed in general help.
    application_description: ?[]const u8 = null,
    /// The allocator to be used for all memory allocations within the `CliCraft` framework.
    allocator: std.mem.Allocator,
    /// Options for error output, including the writer to which errors are logged.
    error_options: struct {
        writer: std.io.AnyWriter,
    },
    /// Options for standard output, including the writer to which general output is directed.
    output_options: struct {
        writer: std.io.AnyWriter,
    },
};

/// The main entry point and orchestrator for building and executing command-line applications.
///
/// `CliCraft` manages commands, flags, arguments, and provides methods for parsing
/// command-line input and executing the appropriate command.
pub const CliCraft = struct {
    /// The global configuration options for this `CliCraft` instance.
    options: GlobalOptions,
    /// The collection of top-level commands managed by this `CliCraft` instance.
    commands: Commands,
    /// A factory for creating `FlagBuilder` instances, ensuring consistent allocator usage.
    flag_factory: FlagFactory,
    /// The unified output stream for standard and error output.
    output_stream: OutputStream,

    /// Initializes a new `CliCraft` instance with the given global options.
    ///
    /// This sets up the internal command registry and the flag factory,
    /// and automatically adds a default 'help' flag to the top-level commands.
    ///
    /// Parameters:
    ///   options: The `GlobalOptions` for the application.
    ///
    /// Returns:
    ///   A new `CliCraft` instance.
    pub fn init(options: GlobalOptions) !CliCraft {
        const output_stream = OutputStream.init(
            options.output_options.writer,
            options.error_options.writer,
        );

        var commands = Commands.init(options.allocator, output_stream);
        try commands.addHelp();

        return .{
            .options = options,
            .commands = commands,
            .flag_factory = FlagFactory.init(options.allocator),
            .output_stream = output_stream,
        };
    }

    /// Creates a new `Command` instance that is executable.
    ///
    /// Parameters:
    ///   name: The name of the command.
    ///   description: A brief description of the command's purpose.
    ///   executable: The function to be executed when this command is invoked.
    ///
    /// Returns:
    ///   A new `Command` instance configured as executable.
    pub fn newExecutableCommand(
        self: CliCraft,
        name: []const u8,
        description: []const u8,
        executable: CommandFn,
    ) !Command {
        return try Command.init(
            name,
            description,
            executable,
            self.output_stream,
            self.options.allocator,
        );
    }

    /// Creates a new `Command` instance that acts as a parent for subcommands.
    ///
    /// Parameters:
    ///   name: The name of the parent command.
    ///   description: A brief description of the parent command's purpose.
    ///
    /// Returns:
    ///   A new `Command` instance configured to hold subcommands.
    pub fn newParentCommand(self: CliCraft, name: []const u8, description: []const u8) !Command {
        return try Command.initParent(
            name,
            description,
            self.output_stream,
            self.options.allocator,
        );
    }

    /// Provides a `FlagBuilder` for creating a new flag.
    ///
    /// Use this to define flags that will be added to commands.
    ///
    /// Parameters:
    ///   name: The long name of the flag (e.g., "verbose").
    ///   description: A brief explanation of the flag's purpose.
    ///   flag_type: The type of value the flag expects (`FlagType.boolean`, `FlagType.int64`, `FlagType.string`).
    ///
    /// Returns:
    ///   A `FlagBuilder` instance ready for further configuration or building.
    pub fn newFlagBuilder(
        self: CliCraft,
        name: []const u8,
        description: []const u8,
        flag_type: FlagType,
    ) FlagBuilder {
        return self.flag_factory.builder(name, description, flag_type);
    }

    /// Provides a `FlagBuilder` for creating a new flag with a default value.
    ///
    /// Use this to define flags that will be added to commands.
    ///
    /// Parameters:
    ///   name: The long name of the flag (e.g., "verbose").
    ///   description: A brief explanation of the flag's purpose.
    ///   flag_value: The default value for the flag, which also determines its type.
    ///
    /// Returns:
    pub fn newFlagBuilderWithDefaultValue(
        self: CliCraft,
        name: []const u8,
        description: []const u8,
        flag_value: FlagValue,
    ) FlagBuilder {
        return self.flag_factory.builderWithDefaultValue(name, description, flag_value);
    }

    /// Adds a new executable command to the top-level of the CLI application.
    ///
    /// Parameters:
    ///   name: The name of the command.
    ///   description: A brief description of the command's purpose.
    ///   executable: The function to be executed when this command is invoked.
    ///
    /// Returns:
    ///   `void` on success, or an error if the command cannot be added (e.g., name conflict).
    pub fn addExecutableCommand(
        self: *CliCraft,
        name: []const u8,
        description: []const u8,
        executable: CommandFn,
    ) !void {
        var command = try self.newExecutableCommand(name, description, executable);
        try self.addCommand(&command);
    }

    /// Adds a new parent command (a command that can have subcommands) to the top-level of the CLI application.
    ///
    /// Parameters:
    ///   name: The name of the parent command.
    ///   description: A brief description of the parent command's purpose.
    ///
    /// Returns:
    ///   `void` on success, or an error if the command cannot be added (e.g., name conflict).
    pub fn addParentCommand(self: *CliCraft, name: []const u8, description: []const u8) !void {
        const command = try self.newParentCommand(name, description);
        try self.addCommand(&command);
    }

    /// Adds a pre-built `Command` instance to the top-level of the CLI application.
    ///
    /// This method allows for adding more complex command definitions.
    ///
    /// Parameters:
    ///   command: A pointer to the `Command` instance to add.
    ///
    /// Returns:
    ///   `void` on success, or an error if the command cannot be added (e.g., name conflict).
    pub fn addCommand(self: *CliCraft, command: *Command) !void {
        var diagnostics: Diagnostics = .{};

        self.commands.add_disallow_child(command, &diagnostics) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    /// Executes the command-line application using arguments provided by `std.os.args()`.
    ///
    /// This method parses the command line, validates input, and executes the appropriate command.
    /// It handles printing help messages and logging diagnostics.
    ///
    /// Returns:
    ///   `void` on successful execution, or an error if parsing or execution fails.
    pub fn execute(self: *CliCraft) !void {
        var diagnostics: Diagnostics = .{};

        try self.commands.execute(
            self.options.application_description,
            Arguments.init(),
            &diagnostics,
        );
    }

    /// Executes the command-line application using a custom slice of arguments.
    ///
    /// This method is useful for testing or when arguments are not coming directly from `std.os.args()`.
    /// It parses the custom arguments, validates input, and executes the appropriate command.
    /// It handles printing help messages and logging diagnostics.
    ///
    /// Parameters:
    ///   arguments: A slice of string slices representing the command-line arguments.
    ///
    /// Returns:
    ///   `void` on successful execution, or an error if parsing or execution fails.
    pub fn executeWithArguments(self: *CliCraft, arguments: []const []const u8) !void {
        var command_line_arguments = try Arguments.initWithArgs(arguments);
        var diagnostics: Diagnostics = .{};

        try self.commands.execute(
            self.options.application_description,
            &command_line_arguments,
            &diagnostics,
        );
    }

    /// Deinitializes the `CliCraft` instance, freeing all associated allocated memory.
    ///
    /// This should be called when the `CliCraft` instance is no longer needed
    /// to prevent memory leaks.
    pub fn deinit(self: *CliCraft) void {
        self.commands.deinit();
    }
};

test {
    // Reference all tests from modules
    std.testing.refAllDecls(@This());
}

var add_command_result: u8 = undefined;
var get_command_result: []const u8 = undefined;

test "execute an executable command with arguments" {
    var cliCraft = try CliCraft.init(.{ .allocator = std.testing.allocator, .error_options = .{
        .writer = std.io.getStdErr().writer().any(),
    }, .output_options = .{
        .writer = std.io.getStdOut().writer().any(),
    } });

    defer cliCraft.deinit();

    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            add_command_result = augend + addend;
            return;
        }
    }.run;

    try cliCraft.addExecutableCommand("add", "adds numbers", runnable);
    try cliCraft.executeWithArguments(&[_][]const u8{ "add", "21", "51" });

    try std.testing.expectEqual(72, add_command_result);
}

test "execute an executable command with arguments and flags" {
    var cliCraft = try CliCraft.init(.{ .allocator = std.testing.allocator, .error_options = .{
        .writer = std.io.getStdErr().writer().any(),
    }, .output_options = .{
        .writer = std.io.getStdOut().writer().any(),
    } });

    defer cliCraft.deinit();

    const runnable = struct {
        pub fn run(parsed_flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            try std.testing.expect(try parsed_flags.getBoolean("verbose"));
            try std.testing.expect(try parsed_flags.getBoolean("priority"));
            try std.testing.expectEqual(23, try parsed_flags.getInt64("timeout"));

            add_command_result = augend + addend;
            return;
        }
    }.run;

    var command = try cliCraft.newExecutableCommand(
        "add",
        "adds numbers",
        runnable,
    );
    try command.addFlag(
        try cliCraft.newFlagBuilder(
            "verbose",
            "Enable verbose output",
            FlagType.boolean,
        ).build(),
    );
    try command.addFlag(try cliCraft.newFlagBuilder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).build());

    try command.addFlag(try cliCraft.newFlagBuilder(
        "timeout",
        "Define timeout",
        FlagValue.type_int64(25),
    ).withShortName('t').build());

    try cliCraft.addCommand(&command);
    try cliCraft.executeWithArguments(
        &[_][]const u8{ "add", "-t", "23", "2", "5", "--verbose", "--priority" },
    );

    try std.testing.expectEqual(7, add_command_result);
}

test "execute a command with subcommand" {
    var cliCraft = try CliCraft.init(.{ .allocator = std.testing.allocator, .error_options = .{
        .writer = std.io.getStdErr().writer().any(),
    }, .output_options = .{
        .writer = std.io.getStdOut().writer().any(),
    } });

    defer cliCraft.deinit();

    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            get_command_result = arguments[0];
        }
    }.run;

    var get_command = try cliCraft.newExecutableCommand(
        "get",
        "get objects",
        runnable,
    );
    var kubectl_command = try cliCraft.newParentCommand(
        "kubectl",
        "kubernetes entry",
    );
    try kubectl_command.addSubcommand(&get_command);

    try cliCraft.addCommand(&kubectl_command);
    try cliCraft.executeWithArguments(&[_][]const u8{ "kubectl", "get", "pods" });

    try std.testing.expectEqual(7, add_command_result);
}
