const std = @import("std");
const FlagType = @import("flags.zig").FlagType;
const FlagErrors = @import("flags.zig").FlagErrors;

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
};
