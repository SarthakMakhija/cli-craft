const std = @import("std");
const FlagType = @import("flags.zig").FlagType;
const FlagErrors = @import("flags.zig").FlagErrors;

pub const Diagnostics = struct {
    diagnostics_type: ?DiagnosticType = null,

    fn print(self: Diagnostics) void {
        if (self.diagnostics_type) |diagnostics_type| switch (diagnostics_type) {
            .FlagNameAlreadyExists => |context| {
                std.debug.print("Error: Flag name '{s}' already exists.\n", .{context.flag_name});
            },
            .FlagShortNameAlreadyExists => |context| {
                std.debug.print("Error: Flag short name '-{c}' already exists for flag '{s}'.\n", .{ context.short_name, context.existing_flag_name });
            },
            .InvalidBoolean => |context| {
                std.debug.print("Error: Invalid boolean value '{s}' for flag '{s}'. Expected 'true' or 'false'.\n", .{ context.value, context.flag_name });
            },
            .InvalidInteger => |context| {
                std.debug.print("Error: Invalid integer value '{s}' for flag '{s}'. Expected a number.\n", .{ context.value, context.flag_name });
            },
            .FlagNotFound => |context| {
                std.debug.print("Error: Flag '{s}' not found.\n", .{context.flag_name});
            },
            .FlagTypeMismatch => |context| {
                std.debug.print("Error: Type mismatch for flag '{s}'. Expected {s}, but value provided was '{s}'.\n", .{ context.flag_name, @tagName(context.expected_type), context.value });
            },
        };
    }

    pub fn reportAndFail(self: *Diagnostics, diagnostic_type: DiagnosticType) anyerror {
        self.diagnostics_type = diagnostic_type;
        return switch (diagnostic_type) {
            .FlagNameAlreadyExists => FlagErrors.FlagNameAlreadyExists,
            .FlagShortNameAlreadyExists => FlagErrors.FlagShortNameAlreadyExists,
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
