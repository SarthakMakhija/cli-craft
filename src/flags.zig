const std = @import("std");
const prettytable = @import("prettytable");

const Diagnostics = @import("diagnostics.zig").Diagnostics;
const DiagnosticType = @import("diagnostics.zig").DiagnosticType;

const OutputStream = @import("stream.zig").OutputStream;

/// The standard long name for the built-in help flag.
pub const HelpFlagName = "help";
/// The standard short name for the built-in help flag.
pub const HelpFlagShortName = "h";
/// The display label used for the help flag in help messages.
pub const HelpFlagDisplayLabel = "--help, -h";

/// Errors that can occur when adding or managing flags.
pub const FlagAddError = error{
    /// A flag with the same name already exists.
    FlagNameAlreadyExists,
    /// A flag with the same short name already exists.
    FlagShortNameAlreadyExists,
    /// A short name conflict occurred during flag merging.
    FlagShortNameMergeConflict,
    /// A general flag conflict was detected (e.g., between parent and child commands).
    FlagConflictDetected,
};

/// Errors that can occur when retrieving a flag's value.
pub const FlagValueGetError = error{
    /// The requested flag type does not match the actual stored value type.
    FlagTypeMismatch,
    /// The specified flag was not found.
    FlagNotFound,
};

/// Errors that can occur during flag value conversion.
pub const FlagValueConversionError = error{
    /// An invalid boolean string (not "true" or "false") was provided.
    InvalidBoolean,
    /// An invalid integer string (not a valid number) was provided.
    InvalidInteger,
};

/// A union of all possible errors related to flag operations.
pub const FlagErrors = FlagAddError || FlagValueGetError || FlagValueConversionError;

/// Defines types of conflicts that can occur between parent and child flags.
pub const FlagConflictType = union(enum) {
    /// Conflict where two flags have the same long name but different short names.
    SameLongNameDifferentShortName: struct {
        short_name: u8,
        other_short_name: u8,
    },
    /// Conflict where two flags have the same short name but different long names.
    SameShortNameDifferentLongName: struct {
        short_name: u8,
        flag_name: []const u8,
        other_flag_name: []const u8,
    },
    /// Conflict where a flag is missing an expected short name.
    MissingShortName: struct {
        expected_short_name: u8,
    },
};

/// Represents a detected conflict between flags.
pub const FlagConflict = struct {
    /// The name of the flag involved in the conflict, if applicable.
    flag_name: ?[]const u8 = null,
    /// The specific type of flag conflict.
    conflict_type: ?FlagConflictType = null,
    /// A boolean indicating whether a conflict was detected (`true`) or not (`false`).
    has_conflict: bool,

    /// Converts this `FlagConflict` into a `DiagnosticType` for reporting.
    /// This method should only be called if `has_conflict` is true.
    ///
    /// Parameters:
    ///   command: The name of the command where the conflict was detected.
    ///   subcommand: The name of the subcommand involved in the conflict, if applicable.
    ///
    /// Returns:
    ///   A `DiagnosticType` union variant detailing the specific conflict.
    pub fn diagnostic_type(self: FlagConflict, command: []const u8, subcommand: []const u8) DiagnosticType {
        std.debug.assert(self.has_conflict);
        switch (self.conflict_type.?) {
            .SameLongNameDifferentShortName => |conflict_type| {
                return .{ .FlagConflictSameLongNameDifferentShortName = .{
                    .command = command,
                    .subcommand = subcommand,
                    .flag_name = self.flag_name.?,
                    .short_name = conflict_type.short_name,
                    .other_short_name = conflict_type.other_short_name,
                } };
            },
            .SameShortNameDifferentLongName => |conflict_type| {
                return .{ .FlagConflictSameShortNameDifferentLongName = .{
                    .command = command,
                    .subcommand = subcommand,
                    .flag_name = conflict_type.flag_name,
                    .other_flag_name = conflict_type.other_flag_name,
                    .short_name = conflict_type.short_name,
                } };
            },
            .MissingShortName => |conflict_type| {
                return .{ .FlagConflictMissingShortName = .{
                    .command = command,
                    .subcommand = subcommand,
                    .flag_name = self.flag_name.?,
                    .expected_short_name = conflict_type.expected_short_name,
                } };
            },
        }
    }
};

/// A collection of `Flag` definitions, managed by name and short name.
///
/// This struct handles adding, retrieving, and deinitializing `Flag` objects,
/// as well as detecting conflicts between flags.
pub const Flags = struct {
    /// A hash map storing flags by their long name.
    flag_by_name: std.StringHashMap(Flag),
    /// A hash map mapping short names to their corresponding long names.
    short_name_to_long_name: std.AutoHashMap(u8, []const u8),
    /// The allocator used for managing the memory of the hash maps and the flags they contain.
    allocator: std.mem.Allocator,

    /// Initializes an empty `Flags` collection.
    ///
    /// Parameters:
    ///   allocator: The allocator to use for the internal hash maps.
    pub fn init(allocator: std.mem.Allocator) Flags {
        return .{
            .flag_by_name = std.StringHashMap(Flag).init(allocator),
            .short_name_to_long_name = std.AutoHashMap(u8, []const u8).init(allocator),
            .allocator = allocator,
        };
    }

    /// Adds a `Flag` to this collection.
    ///
    /// This method checks for name and short name conflicts before adding the flag.
    /// It assumes the `incoming_flag` already owns its internal string data (e.g., created via `Flag.create`).
    ///
    /// Parameters:
    ///   self: A pointer to the `Flags` instance.
    ///   flag: The `Flag` struct to add. Ownership of the flag's internal strings is transferred to this `Flags` collection.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on success, or a `FlagAddError` if a conflict is detected.
    pub fn addFlag(self: *Flags, flag: Flag, diagnostics: *Diagnostics) !void {
        try self.ensureFlagDoesNotExist(flag, diagnostics);
        try self.flag_by_name.put(flag.name, flag);
        if (flag.short_name) |short_name| {
            try self.short_name_to_long_name.put(short_name, flag.name);
        }
    }

    /// Adds the standard "help" flag to this collection.
    ///
    /// This is a convenience method that uses the `FlagFactory` to create the help flag
    /// and adds it to the collection.
    ///
    /// Parameters:
    ///   self: A pointer to the `Flags` instance.
    ///
    /// Returns:
    ///   `void` on success, or an error if the help flag cannot be added.
    pub fn addHelp(self: *Flags) !void {
        const help_flag = try FlagFactory.init(self.allocator).builder(
            HelpFlagName,
            "Show help for command",
            FlagType.boolean,
        ).withShortName(HelpFlagShortName[0]).build();

        try self.flag_by_name.put(help_flag.name, help_flag);
        try self.short_name_to_long_name.put(HelpFlagShortName[0], HelpFlagName);
    }

    /// Ensures that a given flag (by name and short name) does not already exist in this collection.
    ///
    /// This is an internal helper used by `addFlag` to prevent conflicts.
    ///
    /// Parameters:
    ///   self: The `Flags` instance to check against.
    ///   flag: The `Flag` to check for existence.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on success or a `FlagAddError` if a conflict is detected.
    pub fn ensureFlagDoesNotExist(self: Flags, flag: Flag, diagnostics: *Diagnostics) !void {
        if (self.flag_by_name.contains(flag.name)) {
            return diagnostics.reportAndFail(.{ .FlagNameAlreadyExists = .{ .flag_name = flag.name } });
        }
        if (flag.short_name) |short_name| {
            if (self.short_name_to_long_name.contains(short_name)) {
                return diagnostics.reportAndFail(.{ .FlagShortNameAlreadyExists = .{ .short_name = short_name, .existing_flag_name = flag.name } });
            }
        }
    }

    /// Retrieves a `Flag` definition by its long name or short name.
    ///
    /// Parameters:
    ///   self: The `Flags` instance to query.
    ///   flag_name: The name (long or short) of the flag to retrieve.
    ///
    /// Returns:
    ///   A `Flag` struct if found, or `null` if the flag does not exist.
    pub fn get(self: Flags, flag_name: []const u8) ?Flag {
        return self.flag_by_name.get(flag_name) orelse {
            if (flag_name.len > 0) {
                const long_name = self.short_name_to_long_name.get(flag_name[0]);
                if (long_name) |name| {
                    return self.flag_by_name.get(name);
                }
            }
            return null;
        };
    }

    /// Adds flags with default values from this `Flags` collection to a `ParsedFlags` destination.
    ///
    /// Only flags that have a `default_value` and are not already present in the `destination`
    /// `ParsedFlags` will be added.
    ///
    /// Parameters:
    ///   self: The `Flags` collection containing default flag definitions.
    ///   destination: A pointer to the `ParsedFlags` instance to which default flags will be added.
    ///
    /// Returns:
    ///   `void` on success, or an error if adding a flag to `destination` fails.
    pub fn addFlagsWithDefaultValueTo(self: Flags, destination: *ParsedFlags) !void {
        var iterator = self.flag_by_name.iterator();
        while (iterator.next()) |entry| {
            const flag: Flag = entry.value_ptr.*;
            if (flag.default_value) |default_value| {
                if (destination.flag_by_name.contains(flag.name)) {
                    continue;
                }
                try destination.addFlag(ParsedFlag.init(flag.name, default_value));
            }
        }
    }

    /// Merges flags from another `Flags` collection into this one.
    ///
    /// Only flags from `other` that do not already exist in `self` (by name) will be added.
    /// This operation performs a deep copy of the `Flag` structs from `other` into `self`'s
    /// allocator, ensuring `self` owns the new copies.
    ///
    /// Parameters:
    ///   self: A pointer to the `Flags` instance to merge into.
    ///   other: A pointer to the `Flags` instance from which to merge flags.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting errors.
    ///
    /// Returns:
    ///   `void` on success, or an error if adding a flag fails.
    pub fn mergeFrom(self: *Flags, other: *const Flags, diagnostics: *Diagnostics) !void {
        var other_iterator = other.flag_by_name.valueIterator();
        while (other_iterator.next()) |other_flag| {
            if (self.flag_by_name.contains(other_flag.name)) {
                continue;
            }
            const cloned_flag = try Flag.create(
                other_flag.name,
                other_flag.short_name,
                other_flag.description,
                other_flag.flag_type,
                other_flag.default_value,
                other_flag.persistent,
                self.allocator,
            );
            try self.addFlag(cloned_flag, diagnostics);
        }
    }

    /// Determines if there is a conflict between flags, this is typically used to determine if there is
    /// a conflicting flag definition between parent and child command.
    ///
    /// This is typically used to check for conflicts between parent and child command flags.
    /// It checks for:
    /// - Same long name, different short name.
    /// - Same short name, different long name.
    /// - Missing short name when parent has one.
    ///
    /// Parameters:
    ///   self: The `Flags` instance (e.g., parent's flags).
    ///   other: The `Flags` instance to check against `self` (e.g., child's flags).
    ///
    /// Returns:
    ///   A `FlagConflict` struct detailing any conflict found, or indicating no conflict.
    pub fn determineConflictWith(self: Flags, other: Flags) FlagConflict {
        var iterator = self.flag_by_name.iterator();
        while (iterator.next()) |entry| {
            const flag = entry.value_ptr;
            if (other.flag_by_name.contains(flag.name)) {
                const other_flag = other.get(flag.name).?;

                if (flag.short_name) |short_name| {
                    if (other_flag.short_name) |other_short_name| {
                        if (short_name != other_short_name) {
                            return FlagConflict{
                                .flag_name = other_flag.name,
                                .has_conflict = true,
                                .conflict_type = .{ .SameLongNameDifferentShortName = .{
                                    .short_name = short_name,
                                    .other_short_name = other_short_name,
                                } },
                            };
                        }
                    } else {
                        return FlagConflict{
                            .flag_name = other_flag.name,
                            .has_conflict = true,
                            .conflict_type = .{ .MissingShortName = .{
                                .expected_short_name = short_name,
                            } },
                        };
                    }
                }
                // If parent does NOT have a short name, then child having one or not having one is fine.
            }

            if (flag.short_name) |short_name| {
                if (other.short_name_to_long_name.get(short_name)) |other_flag_long_name| {
                    if (!std.mem.eql(u8, other_flag_long_name, flag.name)) {
                        return FlagConflict{
                            .flag_name = other_flag_long_name,
                            .has_conflict = true,
                            .conflict_type = .{ .SameShortNameDifferentLongName = .{
                                .short_name = short_name,
                                .flag_name = flag.name,
                                .other_flag_name = other_flag_long_name,
                            } },
                        };
                    }
                }
            }
        }
        return .{
            .has_conflict = false,
        };
    }

    /// Prints a formatted table of all flags in this collection to the output stream.
    ///
    /// Parameters:
    ///   self: A pointer to the `Flags` instance to print.
    ///   table: A pointer to a `prettytable.Table` instance to populate.
    ///   output_stream: The `OutputStream` to which the table will be printed.
    ///   allocator: The allocator to use for temporary string formatting within the table.
    ///
    /// Returns:
    ///   `void` on success, or an error if printing fails.
    pub fn print(self: *Flags, table: *prettytable.Table, output_stream: OutputStream, allocator: std.mem.Allocator) !void {
        var column_values = std.ArrayList([]const u8).init(allocator);
        defer {
            for (column_values.items) |column_value| {
                allocator.free(column_value);
            }
            column_values.deinit();
        }

        try output_stream.printAll("Flags:\n");
        var iterator = self.flag_by_name.iterator();

        while (iterator.next()) |entry| {
            const flag = entry.value_ptr;
            var flag_name: []const u8 = undefined;

            if (flag.short_name) |short| {
                flag_name = try std.fmt.allocPrint(allocator, "--{s}, -{c}", .{ flag.name, short });
            } else {
                flag_name = try std.fmt.allocPrint(allocator, "--{s}", .{flag.name});
            }

            var description: []const u8 = undefined;
            if (flag.default_value) |default_value| {
                description = switch (default_value) {
                    .boolean => try std.fmt.allocPrint(allocator, "{s} ({s}, default: {any})", .{
                        flag.description,
                        @tagName(flag.flag_type),
                        default_value.boolean,
                    }),
                    .int64 => try std.fmt.allocPrint(allocator, "{s} ({s}, default: {d})", .{
                        flag.description,
                        @tagName(flag.flag_type),
                        default_value.int64,
                    }),
                    .string => try std.fmt.allocPrint(allocator, "{s} ({s}, default: {s})", .{
                        flag.description,
                        @tagName(flag.flag_type),
                        default_value.string,
                    }),
                };
            } else {
                description = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ flag.description, @tagName(
                    flag.flag_type,
                ) });
            }

            try column_values.append(flag_name);
            try column_values.append(description);

            try table.addRow(&[_][]const u8{ flag_name, description });
        }
        return try output_stream.printTable(table);
    }

    /// Deinitializes the `Flags` collection, freeing all allocated memory for its internal
    /// hash maps and the `Flag` objects (and their strings) it contains.
    ///
    /// This should be called when the `Flags` instance is no longer needed.
    ///
    /// Parameters:
    ///   self: A pointer to the `Flags` instance.
    pub fn deinit(self: *Flags) void {
        var iterator = self.flag_by_name.iterator();
        while (iterator.next()) |entry| {
            var flag = entry.value_ptr;
            flag.deinit();
        }
        self.flag_by_name.deinit();
        self.short_name_to_long_name.deinit();
    }
};

/// Defines the possible data types for a flag's value.
pub const FlagType = enum {
    /// A boolean value (true/false).
    boolean,
    /// A 64-bit integer value.
    int64,
    /// A string value.
    string,
};

/// A union type representing the actual value of a flag.
/// The active field corresponds to the `FlagType` of the associated `Flag`.
pub const FlagValue = union(FlagType) {
    /// The boolean value.
    boolean: bool,
    /// The 64-bit integer value.
    int64: i64,
    /// The string value.
    string: []const u8,

    /// Creates a `FlagValue` of type boolean.
    ///
    /// Parameters:
    ///   value: The boolean value.
    pub fn type_boolean(value: bool) FlagValue {
        return .{ .boolean = value };
    }

    /// Creates a `FlagValue` of type 64-bit integer.
    ///
    /// Parameters:
    ///   value: The integer value.
    pub fn type_int64(value: i64) FlagValue {
        return .{ .int64 = value };
    }

    /// Creates a `FlagValue` of type string.
    ///
    /// Parameters:
    ///   value: The string slice value.
    pub fn type_string(value: []const u8) FlagValue {
        return .{ .string = value };
    }

    /// Duplicates the string value within the `FlagValue` if it's a string type.
    /// For other types, it returns the original `FlagValue`.
    ///
    /// Parameters:
    ///   allocator: The allocator to use for duplication.
    ///
    /// Returns:
    ///   A new `FlagValue` with a duplicated string, or the original `FlagValue`.
    ///   Returns an error if string duplication fails.
    fn mayeBeDupe(self: FlagValue, allocator: std.mem.Allocator) !FlagValue {
        return switch (self) {
            .string => |value| FlagValue.type_string(try allocator.dupe(u8, value)),
            else => self,
        };
    }

    /// Retrieves the `FlagType` of this `FlagValue`.
    ///
    /// Parameters:
    ///   self: The `FlagValue` instance.
    ///
    /// Returns:
    ///   The `FlagType` corresponding to the active field of the union.
    fn flag_type(self: FlagValue) FlagType {
        return switch (self) {
            .boolean => FlagType.boolean,
            .int64 => FlagType.int64,
            .string => FlagType.string,
        };
    }

    /// Deinitializes the `FlagValue`, freeing allocated memory if it holds a string.
    ///
    /// Parameters:
    ///   self: A pointer to the `FlagValue` instance.
    ///   allocator: The allocator used for the string.
    fn deinit(self: *FlagValue, allocator: std.mem.Allocator) void {
        return switch (self.*) {
            .string => |value| allocator.free(value),
            else => {},
        };
    }
};

/// Represents a single command-line flag definition.
///
/// A `Flag` defines its name, optional short name, description, expected type,
/// optional default value, and whether it is persistent.
pub const Flag = struct {
    /// The long name of the flag (e.g., "verbose").
    name: []const u8,
    /// An optional single-character short name for the flag (e.g., 'v').
    short_name: ?u8,
    /// A brief description of the flag's purpose.
    description: []const u8,
    /// The expected data type of the flag's value.
    flag_type: FlagType,
    /// An optional default value for the flag.
    default_value: ?FlagValue,
    /// A boolean indicating if this flag is inherited by subcommands.
    persistent: bool,
    /// The allocator used to manage the memory for the flag's `name`, `description`, and
    /// `default_value.string`.
    allocator: std.mem.Allocator,

    /// Internal constructor for creating a `Flag` instance.
    /// This function performs necessary string duplications to ensure the `Flag`
    /// owns its internal string data.
    ///
    /// Parameters:
    ///   name: The long name of the flag.
    ///   short_name: An optional short name.
    ///   description: The flag's description.
    ///   flag_type: The expected type of the flag's value.
    ///   default_value: An optional default value.
    ///   persistent: Whether the flag is persistent.
    ///   allocator: The allocator to use for internal string duplication.
    ///
    /// Returns:
    ///   A new `Flag` instance.
    ///   Returns an error if memory allocation or string duplication fails.
    fn create(
        name: []const u8,
        short_name: ?u8,
        description: []const u8,
        flag_type: FlagType,
        default_value: ?FlagValue,
        persistent: bool,
        allocator: std.mem.Allocator,
    ) !Flag {
        const cloned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(cloned_name);

        const cloned_description = try allocator.dupe(u8, description);
        errdefer allocator.free(cloned_description);

        var cloned_default_value: ?FlagValue = null;
        if (default_value) |default| {
            cloned_default_value = try default.mayeBeDupe(allocator);
            errdefer allocator.free(cloned_default_value);
        }

        return .{
            .name = cloned_name,
            .short_name = short_name,
            .description = cloned_description,
            .flag_type = flag_type,
            .default_value = cloned_default_value,
            .persistent = persistent,
            .allocator = allocator,
        };
    }

    /// Checks if a given string looks like a flag name (e.g., "--flag" or "-f").
    ///
    /// Parameters:
    ///   name: The string to check.
    ///
    /// Returns:
    ///   `true` if the string resembles a flag name, `false` otherwise.
    pub fn looksLikeFlagName(name: []const u8) bool {
        return (name.len == 2 and name[0] == '-' and name[1] != '-') or
            (name.len > 2 and name[0] == '-' and name[1] == '-');
    }

    /// Checks if a given string looks like a boolean flag value ("true" or "false").
    ///
    /// Parameters:
    ///   value: The string to check.
    ///
    /// Returns:
    ///   `true` if the string is "true" or "false", `false` otherwise.
    pub fn looksLikeBooleanFlagValue(value: []const u8) bool {
        if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false")) return true;
        return false;
    }

    /// Normalizes a flag name by removing leading dashes (e.g., "--flag" becomes "flag", "-f" becomes "f").
    ///
    /// Parameters:
    ///   name: The flag name string to normalize.
    ///
    /// Returns:
    ///   A slice of the normalized flag name.
    pub fn normalizeFlagName(name: []const u8) []const u8 {
        if (name.len > 2 and name[0] == '-' and name[1] == '-') {
            return name[2..];
        } else if (name.len > 1 and name[0] == '-' and name[1] != '-') {
            return name[1..];
        }
        return name;
    }

    /// Converts a string `value` into a `FlagValue` based on the `Flag`'s expected `flag_type`.
    ///
    /// This performs parsing and validation for boolean and integer types.
    ///
    /// Parameters:
    ///   self: The `Flag` definition.
    ///   value: The string value to convert.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting conversion errors.
    ///
    /// Returns:
    ///   A `FlagValue` on successful conversion.
    ///   Returns `FlagValueConversionError` or reports a diagnostic if conversion fails.
    pub fn toFlagValue(self: Flag, value: []const u8, diagnostics: *Diagnostics) !FlagValue {
        return switch (self.flag_type) {
            .boolean => {
                if (std.mem.eql(u8, value, "true")) {
                    return FlagValue.type_boolean(true);
                } else if (std.mem.eql(u8, value, "false")) {
                    return FlagValue.type_boolean(false);
                } else {
                    return diagnostics.reportAndFail(.{ .InvalidBoolean = .{
                        .flag_name = self.name,
                        .value = value,
                    } });
                }
            },
            .int64 => {
                const parsed = std.fmt.parseInt(i64, value, 10) catch {
                    return diagnostics.reportAndFail(.{ .InvalidInteger = .{
                        .flag_name = self.name,
                        .value = value,
                    } });
                };
                return FlagValue.type_int64(parsed);
            },
            .string => return FlagValue.type_string(value),
        };
    }

    /// Deinitializes the `Flag` instance, freeing all allocated memory for its `name`,
    /// `description`, and `default_value.string`.
    ///
    /// This should be called when the `Flag` instance is no longer needed.
    ///
    /// Parameters:
    ///   self: A pointer to the `Flag` instance.
    pub fn deinit(self: *Flag) void {
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        if (self.default_value) |*default| {
            default.deinit(self.allocator);
        }
    }
};

/// A factory for creating `FlagBuilder` instances.
///
/// This centralizes the allocator management for all `Flag` objects
/// created within the CLI framework, ensuring consistent memory ownership.
pub const FlagFactory = struct {
    /// The allocator to be used for all `Flag` objects created by this factory.
    allocator: std.mem.Allocator,

    /// Initializes the `FlagFactory` with a specific allocator.
    ///
    /// Parameters:
    ///   allocator: The allocator to be used.
    pub fn init(allocator: std.mem.Allocator) FlagFactory {
        return .{
            .allocator = allocator,
        };
    }

    /// Creates a new `FlagBuilder` for a boolean, integer, or string flag.
    ///
    /// This method automatically uses the factory's configured allocator.
    ///
    /// Parameters:
    ///   name: The long name of the flag (e.g., "verbose").
    ///   description: A brief explanation of the flag's purpose.
    ///   flag_type: The type of value the flag expects (`FlagType.boolean`, `FlagType.int64`, `FlagType.string`).
    ///
    /// Returns:
    ///   A `FlagBuilder` instance ready for further configuration or building.
    pub fn builder(
        self: FlagFactory,
        name: []const u8,
        description: []const u8,
        flag_type: FlagType,
    ) FlagBuilder {
        return FlagBuilder.init(
            name,
            description,
            flag_type,
            self.allocator,
        );
    }

    /// Creates a new `FlagBuilder` for a flag with a default value.
    ///
    /// This method automatically uses the factory's configured allocator.
    /// The `flag_type` is inferred from the `flag_value`.
    ///
    /// Parameters:
    ///   name: The long name of the flag.
    ///   description: A brief explanation of the flag's purpose.
    ///   flag_value: The default value for the flag.
    ///
    /// Returns:
    ///   A `FlagBuilder` instance ready for further configuration or building.
    pub fn builderWithDefaultValue(
        self: FlagFactory,
        name: []const u8,
        description: []const u8,
        flag_value: FlagValue,
    ) FlagBuilder {
        return FlagBuilder.initWithDefaultValue(
            name,
            description,
            flag_value,
            self.allocator,
        );
    }
};

/// A builder for constructing `Flag` instances.
///
/// This struct provides a fluent API to configure the properties of a `Flag`
/// before it is built.
pub const FlagBuilder = struct {
    name: []const u8,
    description: []const u8,
    short_name: ?u8 = null,
    default_value: ?FlagValue = null,
    flag_type: FlagType,
    persistent: bool = false,
    allocator: std.mem.Allocator,

    // Private initialization methods, used by FlagFactory
    fn init(name: []const u8, description: []const u8, flag_type: FlagType, allocator: std.mem.Allocator) FlagBuilder {
        return .{
            .name = name,
            .description = description,
            .flag_type = flag_type,
            .persistent = false,
            .allocator = allocator,
        };
    }

    fn initWithDefaultValue(name: []const u8, description: []const u8, value: FlagValue, allocator: std.mem.Allocator) FlagBuilder {
        return .{
            .name = name,
            .description = description,
            .flag_type = value.flag_type(),
            .default_value = value,
            .persistent = false,
            .allocator = allocator,
        };
    }

    /// Sets an optional short name for the flag.
    ///
    /// Parameters:
    ///   self: The `FlagBuilder` instance.
    ///   short_name: The single-character short name.
    ///
    /// Returns:
    ///   The modified `FlagBuilder` instance for chaining.
    pub fn withShortName(self: FlagBuilder, short_name: u8) FlagBuilder {
        var new_self = self;
        new_self.short_name = short_name;
        return new_self;
    }

    /// Marks the flag as persistent, meaning it will be inherited by subcommands of a command.
    ///
    /// Parameters:
    ///   self: The `FlagBuilder` instance.
    ///
    /// Returns:
    ///   The modified `FlagBuilder` instance for chaining.
    pub fn markPersistent(self: FlagBuilder) FlagBuilder {
        var new_self = self;
        new_self.persistent = true;
        return new_self;
    }

    /// Builds the `Flag` instance based on the configured properties.
    ///
    /// This method calls `Flag.create`, which performs the necessary string duplications.
    ///
    /// Parameters:
    ///   self: The `FlagBuilder` instance.
    ///
    /// Returns:
    ///   A new `Flag` instance.
    ///   Returns an error if `Flag.create` fails (e.g., memory allocation).
    pub fn build(self: FlagBuilder) !Flag {
        return Flag.create(
            self.name,
            self.short_name,
            self.description,
            self.flag_type,
            self.default_value,
            self.persistent,
            self.allocator,
        );
    }
};

/// Represents a single flag that has been parsed from the command line,
/// containing its normalized name and its parsed value.
pub const ParsedFlag = struct {
    /// The normalized name of the parsed flag.
    name: []const u8,
    /// The parsed value of the flag.
    value: FlagValue,

    /// Initializes a `ParsedFlag` instance.
    ///
    /// Parameters:
    ///   name: The normalized name of the flag.
    ///   value: The `FlagValue` representing the parsed value.
    pub fn init(name: []const u8, value: FlagValue) ParsedFlag {
        return .{ .name = name, .value = value };
    }
};

/// A collection of `ParsedFlag` instances, providing easy access to parsed flag values.
pub const ParsedFlags = struct {
    /// A hash map storing `ParsedFlag` instances by their name.
    flag_by_name: std.StringHashMap(ParsedFlag),

    /// Initializes an empty `ParsedFlags` collection.
    ///
    /// Parameters:
    ///   allocator: The allocator to use for the internal hash map.
    pub fn init(allocator: std.mem.Allocator) ParsedFlags {
        return .{ .flag_by_name = std.StringHashMap(ParsedFlag).init(allocator) };
    }

    /// Adds a `ParsedFlag` to the collection.
    ///
    /// If a flag with the same name already exists, it will be overwritten.
    ///
    /// Parameters:
    ///   self: A pointer to the `ParsedFlags` instance.
    ///   flag: The `ParsedFlag` to add.
    ///
    /// Returns:
    ///   `void` on success, or an error if the underlying hash map operation fails.
    pub fn addFlag(self: *ParsedFlags, flag: ParsedFlag) !void {
        try self.flag_by_name.put(flag.name, flag);
    }

    /// Updates an existing `ParsedFlag` in the collection or adds it if it doesn't exist.
    ///
    /// Parameters:
    ///   self: A pointer to the `ParsedFlags` instance.
    ///   flag: The `ParsedFlag` to update or add.
    ///
    /// Returns:
    ///   `void` on success, or an error if the underlying hash map operation fails.
    pub fn updateFlag(
        self: *ParsedFlags,
        flag: ParsedFlag,
    ) !void {
        try self.flag_by_name.put(flag.name, flag);
    }

    /// Retrieves the boolean value of a parsed flag.
    ///
    /// Parameters:
    ///   self: The `ParsedFlags` instance.
    ///   name: The name of the flag.
    ///
    /// Returns:
    ///   The boolean value.
    ///   Returns `FlagValueGetError.FlagNotFound` if the flag doesn't exist.
    ///   Returns `FlagValueGetError.FlagTypeMismatch` if the flag is not a boolean type.
    pub fn getBoolean(self: ParsedFlags, name: []const u8) FlagValueGetError!bool {
        const flag = self.flag_by_name.get(name) orelse return FlagValueGetError.FlagNotFound;
        switch (flag.value) {
            .boolean => return flag.value.boolean,
            else => return FlagValueGetError.FlagTypeMismatch,
        }
    }

    /// Retrieves the 64-bit integer value of a parsed flag.
    ///
    /// Parameters:
    ///   self: The `ParsedFlags` instance.
    ///   name: The name of the flag.
    ///
    /// Returns:
    ///   The integer value.
    ///   Returns `FlagValueGetError.FlagNotFound` if the flag doesn't exist.
    ///   Returns `FlagValueGetError.FlagTypeMismatch` if the flag is not an integer type.
    pub fn getInt64(self: ParsedFlags, name: []const u8) FlagValueGetError!i64 {
        const flag = self.flag_by_name.get(name) orelse return FlagValueGetError.FlagNotFound;
        switch (flag.value) {
            .int64 => return flag.value.int64,
            else => return FlagValueGetError.FlagTypeMismatch,
        }
    }

    /// Retrieves the string value of a parsed flag.
    ///
    /// Parameters:
    ///   self: The `ParsedFlags` instance.
    ///   name: The name of the flag.
    ///
    /// Returns:
    ///   The string slice value.
    ///   Returns `FlagValueGetError.FlagNotFound` if the flag doesn't exist.
    ///   Returns `FlagValueGetError.FlagTypeMismatch` if the flag is not a string type.
    pub fn getString(self: ParsedFlags, name: []const u8) FlagValueGetError![]const u8 {
        const flag = self.flag_by_name.get(name) orelse return FlagValueGetError.FlagNotFound;
        switch (flag.value) {
            .string => return flag.value.string,
            else => return FlagValueGetError.FlagTypeMismatch,
        }
    }

    /// Merges parsed flags from another `ParsedFlags` collection into this one.
    ///
    /// Only flags from `other` that do not already exist in `self` will be added.
    /// This operation performs a shallow copy of `ParsedFlag` structs.
    ///
    /// Parameters:
    ///   self: A pointer to the `ParsedFlags` instance to merge into.
    ///   other: A pointer to the `ParsedFlags` instance from which to merge.
    ///
    /// Returns:
    ///   `void` on success, or an error if adding a flag fails.
    pub fn mergeFrom(self: *ParsedFlags, other: *const ParsedFlags) !void {
        var other_iterator = other.flag_by_name.valueIterator();
        while (other_iterator.next()) |other_flag| {
            if (self.flag_by_name.contains(other_flag.name)) {
                continue;
            }
            try self.addFlag(other_flag.*);
        }
    }

    /// Checks if the "help" flag (or its short alias) is present in the parsed flags.
    ///
    /// Parameters:
    ///   self: The `ParsedFlags` instance.
    ///
    /// Returns:
    ///   `true` if the help flag is found, `false` otherwise.
    pub fn containsHelp(self: ParsedFlags) bool {
        return self.flag_by_name.contains(HelpFlagName) or self.flag_by_name.contains(HelpFlagShortName);
    }

    /// Deinitializes the `ParsedFlags` collection, freeing its internal hash map.
    ///
    /// Note: This assumes that `ParsedFlag.deinit` is handled by the `ParsedFlag`
    /// itself if it contains allocated memory (like strings).
    ///
    /// Parameters:
    ///   self: A pointer to the `ParsedFlags` instance.
    pub fn deinit(self: *ParsedFlags) void {
        self.flag_by_name.deinit();
    }
};

test "flag conflict same long name with different short name to diagnostic type" {
    const conflict = FlagConflict{
        .conflict_type = .{ .SameLongNameDifferentShortName = .{ .short_name = 'n', .other_short_name = 'v' } },
        .flag_name = "namespace",
        .has_conflict = true,
    };
    const diagnostics_type = conflict.diagnostic_type("kubectl", "get");

    try std.testing.expectEqualStrings("kubectl", diagnostics_type.FlagConflictSameLongNameDifferentShortName.command);
    try std.testing.expectEqualStrings("get", diagnostics_type.FlagConflictSameLongNameDifferentShortName.subcommand);
    try std.testing.expectEqualStrings("namespace", diagnostics_type.FlagConflictSameLongNameDifferentShortName.flag_name);
    try std.testing.expectEqual('n', diagnostics_type.FlagConflictSameLongNameDifferentShortName.short_name);
    try std.testing.expectEqual('v', diagnostics_type.FlagConflictSameLongNameDifferentShortName.other_short_name);
}

test "flag conflict same short name with different long name to diagnostic type" {
    const conflict = FlagConflict{
        .conflict_type = .{ .SameShortNameDifferentLongName = .{
            .short_name = 'n',
            .flag_name = "namespace",
            .other_flag_name = "verbose",
        } },
        .flag_name = "namespace",
        .has_conflict = true,
    };
    const diagnostics_type = conflict.diagnostic_type("kubectl", "get");

    try std.testing.expectEqualStrings("kubectl", diagnostics_type.FlagConflictSameShortNameDifferentLongName.command);
    try std.testing.expectEqualStrings("get", diagnostics_type.FlagConflictSameShortNameDifferentLongName.subcommand);
    try std.testing.expectEqualStrings("namespace", diagnostics_type.FlagConflictSameShortNameDifferentLongName.flag_name);
    try std.testing.expectEqualStrings("verbose", diagnostics_type.FlagConflictSameShortNameDifferentLongName.other_flag_name);
    try std.testing.expectEqual('n', diagnostics_type.FlagConflictSameShortNameDifferentLongName.short_name);
}

test "flag conflict missing short name to diagnostic type" {
    const conflict = FlagConflict{
        .conflict_type = .{ .MissingShortName = .{
            .expected_short_name = 'n',
        } },
        .flag_name = "namespace",
        .has_conflict = true,
    };
    const diagnostics_type = conflict.diagnostic_type("kubectl", "get");

    try std.testing.expectEqualStrings("kubectl", diagnostics_type.FlagConflictMissingShortName.command);
    try std.testing.expectEqualStrings("get", diagnostics_type.FlagConflictMissingShortName.subcommand);
    try std.testing.expectEqual('n', diagnostics_type.FlagConflictMissingShortName.expected_short_name);
}

test "build a boolean flag with name and description" {
    var verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build();

    defer verbose_flag.deinit();

    try std.testing.expectEqualStrings("verbose", verbose_flag.name);
    try std.testing.expectEqualStrings("Enable verbose output", verbose_flag.description);
    try std.testing.expect(verbose_flag.flag_type == FlagType.boolean);
    try std.testing.expect(verbose_flag.default_value == null);
    try std.testing.expect(verbose_flag.short_name == null);
}

test "build a boolean flag with short name and default value" {
    var verbose_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "verbose",
        "Enable verbose output",
        FlagValue.type_boolean(false),
    ).withShortName('v').build();

    defer verbose_flag.deinit();

    try std.testing.expectEqualStrings("verbose", verbose_flag.name);
    try std.testing.expectEqualStrings("Enable verbose output", verbose_flag.description);
    try std.testing.expectEqual(false, verbose_flag.default_value.?.boolean);
    try std.testing.expectEqual('v', verbose_flag.short_name.?);
}

test "build a int64 flag with name and description" {
    var count_flag = try FlagFactory.init(std.testing.allocator).builder(
        "count",
        "Count items",
        FlagType.int64,
    ).build();

    defer count_flag.deinit();

    try std.testing.expectEqualStrings("count", count_flag.name);
    try std.testing.expectEqualStrings("Count items", count_flag.description);
    try std.testing.expect(count_flag.flag_type == FlagType.int64);
    try std.testing.expect(count_flag.default_value == null);
    try std.testing.expect(count_flag.short_name == null);
}

test "build a int64 flag with short name and default value" {
    var count_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "count",
        "Count items",
        FlagValue.type_int64(10),
    ).withShortName('c').build();

    defer count_flag.deinit();

    try std.testing.expectEqualStrings("count", count_flag.name);
    try std.testing.expectEqualStrings("Count items", count_flag.description);

    try std.testing.expectEqual(10, count_flag.default_value.?.int64);
    try std.testing.expectEqual('c', count_flag.short_name.?);
}

test "build a string flag with name and description" {
    var namespace_flag = try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define the namespace",
        FlagType.string,
    ).build();

    defer namespace_flag.deinit();

    try std.testing.expectEqualStrings("namespace", namespace_flag.name);
    try std.testing.expectEqualStrings("Define the namespace", namespace_flag.description);
    try std.testing.expect(namespace_flag.default_value == null);
    try std.testing.expect(namespace_flag.short_name == null);
}

test "build a string flag with short name and default value" {
    var namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    defer namespace_flag.deinit();

    try std.testing.expectEqualStrings("namespace", namespace_flag.name);
    try std.testing.expectEqualStrings("Define the namespace", namespace_flag.description);
    try std.testing.expectEqualStrings("default_namespace", namespace_flag.default_value.?.string);
    try std.testing.expect(namespace_flag.flag_type == FlagType.string);
    try std.testing.expectEqual('n', namespace_flag.short_name.?);
}

test "build a persistent flag" {
    var namespace_flag = try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define the namespace",
        FlagType.string,
    ).markPersistent().build();

    defer namespace_flag.deinit();

    try std.testing.expect(namespace_flag.persistent);
}

test "build a non-persistent flag" {
    var namespace_flag = try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define the namespace",
        FlagType.string,
    ).build();

    defer namespace_flag.deinit();

    try std.testing.expect(namespace_flag.persistent == false);
}

test "looks like a flag name 1" {
    try std.testing.expect(Flag.looksLikeFlagName("--verbose"));
}

test "looks like a flag name 2" {
    try std.testing.expect(Flag.looksLikeFlagName("-v"));
}

test "does not look like a flag name 1" {
    try std.testing.expect(Flag.looksLikeFlagName("-") == false);
}

test "does not look like a flag name 2" {
    try std.testing.expect(Flag.looksLikeFlagName("--") == false);
}

test "does not look like a flag name 3" {
    try std.testing.expect(Flag.looksLikeFlagName("-vv") == false);
}

test "does not look like a flag name 4" {
    try std.testing.expect(Flag.looksLikeFlagName("argument") == false);
}

test "normalize a flag name with long name" {
    const normalized = Flag.normalizeFlagName("--verbose");
    try std.testing.expectEqualStrings("verbose", normalized);
}

test "normalize a flag name with short name" {
    const normalized = Flag.normalizeFlagName("-v");
    try std.testing.expectEqualStrings("v", normalized);
}

test "normalize a flag name which is already normalized or is not a flag" {
    const normalized = Flag.normalizeFlagName("pods");
    try std.testing.expectEqualStrings("pods", normalized);
}

test "attempt to add a flag with an existing name" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    var namespace_counting_flag = try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Count namespaces",
        FlagType.int64,
    ).withShortName('n').build();

    defer namespace_counting_flag.deinit();

    try std.testing.expectError(FlagAddError.FlagNameAlreadyExists, flags.addFlag(namespace_counting_flag, &diagnostics));

    const diagnostic_type = diagnostics.diagnostics_type.?.FlagNameAlreadyExists;
    try std.testing.expectEqualStrings("namespace", diagnostic_type.flag_name);
}

test "attempt to add a flag with an existing short name" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    var namespace_counting_flag = try FlagFactory.init(std.testing.allocator).builder(
        "counter",
        "Count namespaces",
        FlagType.int64,
    ).withShortName('n').build();

    defer namespace_counting_flag.deinit();

    try std.testing.expectError(FlagAddError.FlagShortNameAlreadyExists, flags.addFlag(namespace_counting_flag, &diagnostics));

    const diagnostic_type = diagnostics.diagnostics_type.?.FlagShortNameAlreadyExists;
    try std.testing.expectEqual('n', diagnostic_type.short_name);
}

test "add a flag and check its existence by name" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    try std.testing.expectEqualStrings("namespace", flags.get("namespace").?.name);
}

test "determine conflict based on missing short name for a flag name" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    const other_namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).build();

    var other_flags = Flags.init(std.testing.allocator);
    defer other_flags.deinit();
    try other_flags.addFlag(other_namespace_flag, &diagnostics);

    const conflict = flags.determineConflictWith(other_flags);
    try std.testing.expectEqualStrings("namespace", conflict.flag_name.?);
    try std.testing.expectEqual('n', conflict.conflict_type.?.MissingShortName.expected_short_name);
}

test "determine conflict based on different short name for the same flag name" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    const other_namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('p').build();

    var other_flags = Flags.init(std.testing.allocator);
    defer other_flags.deinit();
    try other_flags.addFlag(other_namespace_flag, &diagnostics);

    const conflict = flags.determineConflictWith(other_flags);
    try std.testing.expectEqualStrings("namespace", conflict.flag_name.?);
    try std.testing.expectEqual('n', conflict.conflict_type.?.SameLongNameDifferentShortName.short_name);
    try std.testing.expectEqual('p', conflict.conflict_type.?.SameLongNameDifferentShortName.other_short_name);
}

test "determine conflict based on different long name for the same flag short name" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    const other_namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "verbose",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var other_flags = Flags.init(std.testing.allocator);
    defer other_flags.deinit();
    try other_flags.addFlag(other_namespace_flag, &diagnostics);

    const conflict = flags.determineConflictWith(other_flags);

    try std.testing.expectEqualStrings("verbose", conflict.flag_name.?);
    try std.testing.expectEqualStrings("namespace", conflict.conflict_type.?.SameShortNameDifferentLongName.flag_name);
    try std.testing.expectEqualStrings("verbose", conflict.conflict_type.?.SameShortNameDifferentLongName.other_flag_name);
    try std.testing.expectEqual('n', conflict.conflict_type.?.SameShortNameDifferentLongName.short_name);
}

test "has no conflict" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    const other_namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var other_flags = Flags.init(std.testing.allocator);
    defer other_flags.deinit();
    try other_flags.addFlag(other_namespace_flag, &diagnostics);

    const conflict = flags.determineConflictWith(other_flags);
    try std.testing.expect(conflict.has_conflict == false);
}

test "print flags" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("cli-craft"),
    ).withShortName('n').build();

    const verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Define verbose output",
        FlagType.boolean,
    ).withShortName('v').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);
    try flags.addFlag(verbose_flag, &diagnostics);

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();

    var table = prettytable.Table.init(std.testing.allocator);
    defer table.deinit();

    table.setFormat(prettytable.FORMAT_CLEAN);

    try flags.print(&table, OutputStream.initStdErrWriter(writer.any()), std.testing.allocator);
    const value = buffer.items;

    try std.testing.expect(std.mem.indexOf(u8, value, "--verbose").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "-v").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "(boolean)").? > 0);

    try std.testing.expect(std.mem.indexOf(u8, value, "--namespace").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "-n").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, value, "(string, default: cli-craft)").? > 0);
}

test "add help flag" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addHelp();

    try std.testing.expectEqualStrings("help", flags.get("help").?.name);
    try std.testing.expectEqualStrings("help", flags.get("h").?.name);
}

test "add a flag and check its existence by short name" {
    const namespace_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    try std.testing.expectEqualStrings("namespace", flags.get("n").?.name);
}

test "check the existence of a non-existing flag by name" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try std.testing.expect(flags.get("n") == null);
}

test "check the existence of a non-existing flag by short name" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try std.testing.expect(flags.get("v") == null);
}

test "convert a string to true boolean flag value" {
    var verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build();

    defer verbose_flag.deinit();

    var diagnostics: Diagnostics = .{};
    const flag_value = try verbose_flag.toFlagValue("true", &diagnostics);

    try std.testing.expect(flag_value.boolean);
}

test "convert a string to false boolean flag value" {
    var verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build();

    defer verbose_flag.deinit();

    var diagnostics: Diagnostics = .{};
    const flag_value = try verbose_flag.toFlagValue("false", &diagnostics);

    try std.testing.expect(flag_value.boolean == false);
}

test "attempt to convert a string to true boolean flag value" {
    var verbose_flag = try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Enable verbose output",
        FlagType.boolean,
    ).build();

    defer verbose_flag.deinit();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(FlagValueConversionError.InvalidBoolean, verbose_flag.toFlagValue("nothing", &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.InvalidBoolean;
    try std.testing.expectEqualStrings("verbose", diagnostics_type.flag_name);
    try std.testing.expectEqual("nothing", diagnostics_type.value);
}

test "convert a string to int64 flag value" {
    var count_flag = try FlagFactory.init(std.testing.allocator).builder(
        "count",
        "Count items",
        FlagType.int64,
    ).build();

    defer count_flag.deinit();

    var diagnostics: Diagnostics = .{};
    const flag_value = try count_flag.toFlagValue("123", &diagnostics);

    try std.testing.expectEqual(123, flag_value.int64);
}

test "attempt to convert a string to int64 flag value" {
    var count_flag = try FlagFactory.init(std.testing.allocator).builder(
        "count",
        "Count items",
        FlagType.int64,
    ).build();

    defer count_flag.deinit();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(FlagValueConversionError.InvalidInteger, count_flag.toFlagValue("nothing", &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.InvalidInteger;
    try std.testing.expectEqualStrings("count", diagnostics_type.flag_name);
    try std.testing.expectEqual("nothing", diagnostics_type.value);
}

test "convert a string to string flag value" {
    var namespace_flag = try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define namespace",
        FlagType.string,
    ).build();

    defer namespace_flag.deinit();

    var diagnostics: Diagnostics = .{};
    const flag_value = try namespace_flag.toFlagValue("cli-craft", &diagnostics);

    try std.testing.expectEqualStrings("cli-craft", flag_value.string);
}

test "merge flags containing unique flags" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = Flags.init(std.testing.allocator);
    defer other_flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build(), &diagnostics);

    try other_flags.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Define verbose output",
        FlagType.boolean,
    ).build(), &diagnostics);

    try flags.mergeFrom(&other_flags, &diagnostics);

    try std.testing.expectEqualStrings("namespace", flags.get("n").?.name);
    try std.testing.expectEqualStrings("verbose", flags.get("verbose").?.name);
}

test "merge flags containing flags with same name" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = Flags.init(std.testing.allocator);
    defer other_flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "namespace",
        "Define the namespace",
        FlagValue.type_string("default_namespace"),
    ).withShortName('n').build(), &diagnostics);

    try other_flags.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "verbose",
        "Define verbose output",
        FlagType.boolean,
    ).build(), &diagnostics);

    try other_flags.addFlag(try FlagFactory.init(std.testing.allocator).builder(
        "namespace",
        "Define namespace",
        FlagType.string,
    ).build(), &diagnostics);

    try flags.mergeFrom(&other_flags, &diagnostics);

    try std.testing.expectEqualStrings("namespace", flags.get("n").?.name);
    try std.testing.expectEqualStrings("default_namespace", flags.get("n").?.default_value.?.string);
    try std.testing.expectEqualStrings("verbose", flags.get("verbose").?.name);
}

test "build a parsed flag with name and value" {
    const counting_flag = ParsedFlag.init("count", FlagValue.type_int64(10));
    try std.testing.expectEqualStrings("count", counting_flag.name);
    try std.testing.expect(counting_flag.value.int64 == 10);
}

test "add a parsed boolean flag" {
    const verbose_flag = ParsedFlag.init("verbose", FlagValue.type_boolean(false));

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    try parsed_flags.addFlag(verbose_flag);
    try std.testing.expect(try parsed_flags.getBoolean("verbose") == false);
}

test "add a parsed boolean flag and attempt to get an i64 flag" {
    const verbose_flag = ParsedFlag.init("verbose", FlagValue.type_boolean(false));

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    try parsed_flags.addFlag(verbose_flag);
    try std.testing.expectError(FlagValueGetError.FlagTypeMismatch, parsed_flags.getInt64("verbose"));
}

test "add a parsed int64 flag" {
    const counting_flag = ParsedFlag.init("count", FlagValue.type_int64(10));

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    try parsed_flags.addFlag(counting_flag);
    try std.testing.expectEqual(10, try parsed_flags.getInt64("count"));
}

test "add a parsed int64 flag and attempt to get a string flag" {
    const counting_flag = ParsedFlag.init("count", FlagValue.type_int64(10));

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    try parsed_flags.addFlag(counting_flag);
    try std.testing.expectError(FlagValueGetError.FlagTypeMismatch, parsed_flags.getString("count"));
}

test "add a parsed string flag" {
    const namespace_flag = ParsedFlag.init("namespace", FlagValue.type_string("k8s"));

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    try parsed_flags.addFlag(namespace_flag);
    try std.testing.expectEqualStrings("k8s", try parsed_flags.getString("namespace"));
}

test "add a parsed string flag and attempt to get a boolean flag" {
    const namespace_flag = ParsedFlag.init("namespace", FlagValue.type_string("k8s"));

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    try parsed_flags.addFlag(namespace_flag);
    try std.testing.expectError(FlagValueGetError.FlagTypeMismatch, parsed_flags.getBoolean("namespace"));
}

test "add a parsed flag with default value" {
    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    const timeout_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "timeout",
        "Define timeout",
        FlagValue.type_int64(25),
    ).build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(timeout_flag, &diagnostics);

    try flags.addFlagsWithDefaultValueTo(&parsed_flags);

    try std.testing.expect(parsed_flags.flag_by_name.contains("timeout"));
    try std.testing.expectEqual(25, try parsed_flags.getInt64("timeout"));
}

test "attempt to add a parsed flag with default value when the flag is already present" {
    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    try parsed_flags.addFlag(ParsedFlag.init("timeout", FlagValue.type_int64(30)));
    defer parsed_flags.deinit();

    const timeout_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "timeout",
        "Define timeout",
        FlagValue.type_int64(25),
    ).build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(timeout_flag, &diagnostics);

    try flags.addFlagsWithDefaultValueTo(&parsed_flags);

    try std.testing.expect(parsed_flags.flag_by_name.contains("timeout"));
    try std.testing.expectEqual(30, try parsed_flags.getInt64("timeout"));
}

test "add a couple of parsed flags with default value" {
    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    const timeout_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "timeout",
        "Define timeout",
        FlagValue.type_int64(25),
    ).markPersistent().build();

    const verbose_flag = try FlagFactory.init(std.testing.allocator).builderWithDefaultValue(
        "verbose",
        "Display verbose output",
        FlagValue.type_boolean(false),
    ).markPersistent().build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(timeout_flag, &diagnostics);
    try flags.addFlag(verbose_flag, &diagnostics);

    try flags.addFlagsWithDefaultValueTo(&parsed_flags);

    try std.testing.expect(parsed_flags.flag_by_name.contains("timeout"));
    try std.testing.expectEqual(25, try parsed_flags.getInt64("timeout"));

    try std.testing.expect(parsed_flags.flag_by_name.contains("verbose"));
    try std.testing.expect(try parsed_flags.getBoolean("verbose") == false);
}

test "update a parsed flag value" {
    const verbose_flag = ParsedFlag.init("verbose", FlagValue.type_boolean(false));

    var parsed_flags = ParsedFlags.init(std.testing.allocator);
    defer parsed_flags.deinit();

    try parsed_flags.addFlag(verbose_flag);
    try parsed_flags.updateFlag(ParsedFlag.init("verbose", FlagValue.type_boolean(true)));

    try std.testing.expect(try parsed_flags.getBoolean("verbose"));
}

test "merge parsed flags containing unique flags" {
    var flags = ParsedFlags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = ParsedFlags.init(std.testing.allocator);
    defer other_flags.deinit();

    try flags.addFlag(ParsedFlag.init("namespace", FlagValue.type_string("default_namespace")));
    try other_flags.addFlag(ParsedFlag.init("verbose", FlagValue.type_boolean(false)));

    try flags.mergeFrom(&other_flags);

    try std.testing.expectEqualStrings("default_namespace", try flags.getString("namespace"));
    try std.testing.expect(try flags.getBoolean("verbose") == false);
}

test "merge parsed flags containing duplicate flags" {
    var flags = ParsedFlags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = ParsedFlags.init(std.testing.allocator);
    defer other_flags.deinit();

    try flags.addFlag(ParsedFlag.init("namespace", FlagValue.type_string("default_namespace")));
    try other_flags.addFlag(ParsedFlag.init("verbose", FlagValue.type_boolean(false)));
    try other_flags.addFlag(ParsedFlag.init("namespace", FlagValue.type_string("default_namespace again")));

    try flags.mergeFrom(&other_flags);

    try std.testing.expectEqualStrings("default_namespace", try flags.getString("namespace"));
    try std.testing.expect(try flags.getBoolean("verbose") == false);
}

test "parsed flags contain help flag 1" {
    var flags = ParsedFlags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = ParsedFlags.init(std.testing.allocator);
    defer other_flags.deinit();

    try flags.addFlag(ParsedFlag.init("help", FlagValue.type_string("")));
    try other_flags.addFlag(ParsedFlag.init("verbose", FlagValue.type_boolean(false)));
    try other_flags.addFlag(ParsedFlag.init("namespace", FlagValue.type_string("default_namespace again")));

    try std.testing.expect(flags.containsHelp());
}

test "parsed flags contain help flag 2" {
    var flags = ParsedFlags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = ParsedFlags.init(std.testing.allocator);
    defer other_flags.deinit();

    try flags.addFlag(ParsedFlag.init("h", FlagValue.type_string("")));
    try other_flags.addFlag(ParsedFlag.init("verbose", FlagValue.type_boolean(false)));
    try other_flags.addFlag(ParsedFlag.init("namespace", FlagValue.type_string("default_namespace again")));

    try std.testing.expect(flags.containsHelp());
}

test "parsed flags does not contain help flag" {
    var flags = ParsedFlags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = ParsedFlags.init(std.testing.allocator);
    defer other_flags.deinit();

    try other_flags.addFlag(ParsedFlag.init("verbose", FlagValue.type_boolean(false)));
    try other_flags.addFlag(ParsedFlag.init("namespace", FlagValue.type_string("default_namespace again")));

    try std.testing.expect(flags.containsHelp() == false);
}
