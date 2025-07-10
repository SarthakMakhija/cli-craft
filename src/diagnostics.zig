const std = @import("std");
const FlagType = @import("flags.zig").FlagType;
const FlagErrors = @import("flags.zig").FlagErrors;
const CommandErrors = @import("commands.zig").CommandErrors;

const ErrorLog = @import("log.zig").ErrorLog;

pub const Diagnostics = struct {
    diagnostics_type: ?DiagnosticType = null,

    pub fn log_using(self: Diagnostics, error_log: ErrorLog) void {
        if (self.diagnostics_type) |diagnostics_type| switch (diagnostics_type) {
            .FlagNameAlreadyExists => |context| {
                error_log.log("Error: Flag name '{s}' already exists.\n", .{context.flag_name});
            },
            .FlagShortNameAlreadyExists => |context| {
                error_log.log("Error: Flag short name '-{c}' already exists for flag '{s}'.\n", .{ context.short_name, context.existing_flag_name });
            },
            .FlagShortNameMergeConflict => |context| {
                error_log.log("Error: During flag merge, short name '{c}' for flag '{s}' conflicts with existing flag '{s}'. This is an ambiguous CLI definition.\n", .{ context.short_name, context.flag_name, context.conflicting_flag_name });
            },
            .InvalidBoolean => |context| {
                error_log.log("Error: Invalid boolean value '{s}' for flag '{s}'. Expected 'true' or 'false'.\n", .{ context.value, context.flag_name });
            },
            .InvalidInteger => |context| {
                error_log.log("Error: Invalid integer value '{s}' for flag '{s}'. Expected a number.\n", .{ context.value, context.flag_name });
            },
            .FlagNotFound => |context| {
                error_log.log("Error: Flag '{s}' not found.\n", .{context.flag_name});
            },
            .FlagTypeMismatch => |context| {
                error_log.log("Error: Type mismatch for flag '{s}'. Expected {s}, but value provided was '{s}'.\n", .{ context.flag_name, @tagName(context.expected_type), context.value });
            },
            .NoFlagsAddedToCommand => |context| {
                error_log.log("Error: No flags added to the command but found the flag '{s}'.\n", .{context.parsed_flag});
            },
            .NoFlagValueProvided => |context| {
                error_log.log("Error: No flag value was provided for the flag '{s}'.\n", .{context.parsed_flag});
            },
            .NoSubcommandProvided => |context| {
                error_log.log("Error: No subcommand provided for the command '{s}'.\n", .{context.command});
            },
            .SubcommandNotAddedToParentCommand => |context| {
                error_log.log("Error: Subcommand '{s}' not added to the parent command '{s}'.\n", .{ context.subcommand, context.command });
            },
            .SubCommandNameSameAsParent => |context| {
                error_log.log("Error: Subcommand name '{s}' is same as the parent command name.\n", .{context.command});
            },
            .SubCommandAddedToExecutable => |context| {
                error_log.log("Error: Subcommand '{s}' added to an executable command '{s}'.\n", .{ context.command, context.subcommand });
            },
            .ChildCommandAdded => |context| {
                error_log.log("Error: Child command command '{s}' added to Cli-Craft.\n", .{context.command});
            },
            .CommandNameAlreadyExists => |context| {
                error_log.log("Error: Command name '{s}' already exists.\n", .{context.command});
            },
            .CommandAliasAlreadyExists => |context| {
                error_log.log("Error: Command alias '{s}' already exists for the command '{s}'.\n", .{ context.alias, context.existing_command });
            },
            .MissingCommandNameToExecute => |_| {
                error_log.log("Error: No command was provided to execute.\n", .{});
            },
            .CommandNotFound => |context| {
                error_log.log("Error: Command '{s}' not found.\n", .{context.command});
            },
        };
    }

    pub fn reportAndFail(self: *Diagnostics, diagnostic_type: DiagnosticType) anyerror {
        self.diagnostics_type = diagnostic_type;
        return switch (diagnostic_type) {
            .FlagNameAlreadyExists => FlagErrors.FlagNameAlreadyExists,
            .FlagShortNameAlreadyExists => FlagErrors.FlagShortNameAlreadyExists,
            .FlagShortNameMergeConflict => FlagErrors.FlagShortNameMergeConflict,
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
};
