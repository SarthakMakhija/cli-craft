const std = @import("std");
const FlagType = @import("flags.zig").FlagType;
const FlagErrors = @import("flags.zig").FlagErrors;
const CommandErrors = @import("commands.zig").CommandErrors;

const OutputStream = @import("stream.zig").OutputStream;

pub const Diagnostics = struct {
    diagnostics_type: ?DiagnosticType = null,

    pub fn log_using(self: Diagnostics, output_stream: OutputStream) void {
        if (self.diagnostics_type) |diagnostics_type| switch (diagnostics_type) {
            .FlagNameAlreadyExists => |context| {
                output_stream.printError("Error: Flag name '{s}' already exists.\n", .{context.flag_name}) catch {};
            },
            .FlagShortNameAlreadyExists => |context| {
                output_stream.printError("Error: Flag short name '{c}' already exists for flag '{s}'.\n", .{ context.short_name, context.existing_flag_name }) catch {};
            },
            .FlagShortNameMergeConflict => |context| {
                output_stream.printError("Error: During flag merge, short name '{c}' for flag '{s}' conflicts with existing flag '{s}'. This is an ambiguous CLI definition.\n", .{ context.short_name, context.flag_name, context.conflicting_flag_name }) catch {};
            },
            .FlagConflictSameLongNameDifferentShortName => |context| {
                output_stream.printError("Error: Flag conflict detected, same long name but different short name, command: {s}, subcommand: {s}, flag {s}, short name: '{c}', other short name: '{c}'. \n", .{ context.command, context.subcommand, context.flag_name, context.short_name, context.other_short_name }) catch {};
            },
            .FlagConflictSameShortNameDifferentLongName => |context| {
                output_stream.printError("Error: Flag conflict detected, same short name but different long name, command: {s}, subcommand: {s}, flag {s}, other flag name: {s}, short name: '{c}'. \n", .{ context.command, context.subcommand, context.flag_name, context.other_flag_name, context.short_name }) catch {};
            },
            .FlagConflictMissingShortName => |context| {
                output_stream.printError("Error: Flag conflict detected, missing short name, command: {s}, subcommand: {s}, flag {s}, expected short name: '{c}'. \n", .{ context.command, context.subcommand, context.flag_name, context.expected_short_name }) catch {};
            },
            .InvalidBoolean => |context| {
                output_stream.printError("Error: Invalid boolean value '{s}' for flag '{s}'. Expected 'true' or 'false'.\n", .{ context.value, context.flag_name }) catch {};
            },
            .InvalidInteger => |context| {
                output_stream.printError("Error: Invalid integer value '{s}' for flag '{s}'. Expected a number.\n", .{ context.value, context.flag_name }) catch {};
            },
            .FlagNotFound => |context| {
                output_stream.printError("Error: Flag '{s}' not found.\n", .{context.flag_name}) catch {};
            },
            .FlagTypeMismatch => |context| {
                output_stream.printError("Error: Type mismatch for flag '{s}'. Expected {s}, but value provided was '{s}'.\n", .{ context.flag_name, @tagName(context.expected_type), context.value }) catch {};
            },
            .NoFlagsAddedToCommand => |context| {
                output_stream.printError("Error: No flags added to the command but found the flag '{s}'.\n", .{context.parsed_flag}) catch {};
            },
            .NoFlagValueProvided => |context| {
                output_stream.printError("Error: No flag value was provided for the flag '{s}'.\n", .{context.parsed_flag}) catch {};
            },
            .NoSubcommandProvided => |context| {
                output_stream.printError("Error: No subcommand provided for the command '{s}'.\n", .{context.command}) catch {};
            },
            .SubcommandNotAddedToParentCommand => |context| {
                output_stream.printError("Error: Subcommand '{s}' not added to the parent command '{s}'.\n", .{ context.subcommand, context.command }) catch {};
            },
            .SubCommandNameSameAsParent => |context| {
                output_stream.printError("Error: Subcommand name '{s}' is same as the parent command name.\n", .{context.command}) catch {};
            },
            .SubCommandAddedToExecutable => |context| {
                output_stream.printError("Error: Subcommand '{s}' added to an executable command '{s}'.\n", .{ context.command, context.subcommand }) catch {};
            },
            .ChildCommandAdded => |context| {
                output_stream.printError("Error: Child command command '{s}' added to Cli-Craft.\n", .{context.command}) catch {};
            },
            .CommandNameAlreadyExists => |context| {
                output_stream.printError("Error: Command name '{s}' already exists.\n", .{context.command}) catch {};
            },
            .CommandAliasAlreadyExists => |context| {
                output_stream.printError("Error: Command alias '{s}' already exists for the command '{s}'.\n", .{ context.alias, context.existing_command }) catch {};
            },
            .MissingCommandNameToExecute => |_| {
                output_stream.printError("Error: No command was provided to execute.\n", .{}) catch {};
            },
            .CommandNotFound => |context| {
                output_stream.printError("Error: Command '{s}' not found.\n", .{context.command}) catch {};
            },
            .CommandAlreadyFrozen => |context| {
                output_stream.printError("Error: Command '{s}' is already frozen. It cannot be modified after being added as a subcommand or to the top-level CLI.\n", .{context.command}) catch {};
            },
        };
    }

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
        };
    }
};

pub const DiagnosticType = union(enum) {
    FlagNameAlreadyExists: struct {
        flag_name: []const u8,
    },
    FlagShortNameAlreadyExists: struct {
        short_name: u8,
        existing_flag_name: []const u8,
    },
    FlagShortNameMergeConflict: struct {
        short_name: u8,
        flag_name: []const u8,
        conflicting_flag_name: []const u8,
    },
    FlagConflictSameLongNameDifferentShortName: struct {
        command: []const u8,
        subcommand: []const u8,
        flag_name: []const u8,
        short_name: u8,
        other_short_name: u8,
    },
    FlagConflictSameShortNameDifferentLongName: struct {
        command: []const u8,
        subcommand: []const u8,
        flag_name: []const u8,
        other_flag_name: []const u8,
        short_name: u8,
    },
    FlagConflictMissingShortName: struct {
        command: []const u8,
        subcommand: []const u8,
        flag_name: []const u8,
        expected_short_name: u8,
    },
    InvalidBoolean: struct {
        flag_name: []const u8,
        value: []const u8,
    },
    InvalidInteger: struct {
        flag_name: []const u8,
        value: []const u8,
    },
    FlagNotFound: struct {
        flag_name: []const u8,
    },
    FlagTypeMismatch: struct {
        flag_name: []const u8,
        expected_type: FlagType,
        value: []const u8,
    },
    NoFlagsAddedToCommand: struct {
        parsed_flag: []const u8,
    },
    NoFlagValueProvided: struct {
        parsed_flag: []const u8,
    },
    NoSubcommandProvided: struct {
        command: []const u8,
    },
    SubcommandNotAddedToParentCommand: struct {
        command: []const u8,
        subcommand: []const u8,
    },
    SubCommandNameSameAsParent: struct {
        command: []const u8,
    },
    SubCommandAddedToExecutable: struct {
        command: []const u8,
        subcommand: []const u8,
    },
    ChildCommandAdded: struct {
        command: []const u8,
    },
    CommandNameAlreadyExists: struct {
        command: []const u8,
    },
    CommandAliasAlreadyExists: struct {
        alias: []const u8,
        existing_command: []const u8,
    },
    MissingCommandNameToExecute: struct {},
    CommandNotFound: struct {
        command: []const u8,
    },
    CommandAlreadyFrozen: struct {
        command: []const u8,
    },
};
