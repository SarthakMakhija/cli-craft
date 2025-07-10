const std = @import("std");
const Diagnostics = @import("diagnostics.zig").Diagnostics;
const DiagnosticType = @import("diagnostics.zig").DiagnosticType;

pub const FlagAddError = error{
    FlagNameAlreadyExists,
    FlagShortNameAlreadyExists,
    FlagShortNameMergeConflict,
};

pub const FlagValueGetError = error{
    FlagTypeMismatch,
    FlagNotFound,
};

pub const FlagValueConversionError = error{
    InvalidBoolean,
    InvalidInteger,
};

pub const FlagErrors = FlagAddError || FlagValueGetError || FlagValueConversionError;

pub const Flags = struct {
    flag_by_name: std.StringHashMap(Flag),
    short_name_to_long_name: std.AutoHashMap(u8, []const u8),

    pub fn init(allocator: std.mem.Allocator) Flags {
        return .{
            .flag_by_name = std.StringHashMap(Flag).init(allocator),
            .short_name_to_long_name = std.AutoHashMap(u8, []const u8).init(allocator),
        };
    }

    pub fn addFlag(self: *Flags, flag: Flag, diagnostics: *Diagnostics) !void {
        if (self.flag_by_name.contains(flag.name)) {
            return diagnostics.reportAndFail(.{ .FlagNameAlreadyExists = .{ .flag_name = flag.name } });
        }
        if (flag.short_name) |short_name| {
            if (self.short_name_to_long_name.contains(short_name)) {
                return diagnostics.reportAndFail(.{ .FlagShortNameAlreadyExists = .{ .short_name = short_name, .existing_flag_name = flag.name } });
            }
        }

        try self.flag_by_name.put(flag.name, flag);
        if (flag.short_name) |short_name| {
            try self.short_name_to_long_name.put(short_name, flag.name);
        }
    }

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

    pub fn merge(self: *Flags, other: *const Flags, diagnostics: *Diagnostics) !void {
        var other_iterator = other.flag_by_name.valueIterator();
        while (other_iterator.next()) |other_flag| {
            if (self.flag_by_name.contains(other_flag.name)) {
                continue;
            }

            // If the flag has a short name, check for conflicts.
            if (other_flag.short_name) |other_short_name| {
                if (self.short_name_to_long_name.contains(other_short_name)) {
                    return diagnostics.reportAndFail(.{ .FlagShortNameMergeConflict = .{ .short_name = other_short_name, .flag_name = other_flag.name, .conflicting_flag_name = self.short_name_to_long_name.get(other_short_name).? } });
                }
            }
            try self.addFlag(other_flag.*, diagnostics);
        }
    }

    pub fn deinit(self: *Flags) void {
        self.flag_by_name.deinit();
        self.short_name_to_long_name.deinit();
    }
};

pub const FlagType = enum {
    boolean,
    int64,
    string,
};

pub const FlagValue = union(FlagType) {
    boolean: bool,
    int64: i64,
    string: []const u8,

    pub fn type_boolean(value: bool) FlagValue {
        return .{ .boolean = value };
    }

    pub fn type_int64(value: i64) FlagValue {
        return .{ .int64 = value };
    }

    pub fn type_string(value: []const u8) FlagValue {
        return .{ .string = value };
    }

    fn flag_type(self: FlagValue) FlagType {
        return switch (self) {
            .boolean => FlagType.boolean,
            .int64 => FlagType.int64,
            .string => FlagType.string,
        };
    }
};

pub const Flag = struct {
    name: []const u8,
    short_name: ?u8,
    description: []const u8,
    flag_type: FlagType,
    default_value: ?FlagValue,
    persistent: bool,

    fn create(
        name: []const u8,
        short_name: ?u8,
        description: []const u8,
        flag_type: FlagType,
        default_value: ?FlagValue,
        persistent: bool,
    ) Flag {
        return .{
            .name = name,
            .short_name = short_name,
            .description = description,
            .flag_type = flag_type,
            .default_value = default_value,
            .persistent = persistent,
        };
    }

    pub fn builder(name: []const u8, description: []const u8, flag_type: FlagType) FlagBuilder {
        return FlagBuilder.init(name, description, flag_type);
    }

    pub fn builder_with_default_value(name: []const u8, description: []const u8, flag_value: FlagValue) FlagBuilder {
        return FlagBuilder.initWithDefaultValue(name, description, flag_value);
    }

    pub fn looksLikeFlagName(name: []const u8) bool {
        return (name.len == 2 and name[0] == '-' and name[1] != '-') or
            (name.len > 2 and name[0] == '-' and name[1] == '-');
    }

    pub fn looksLikeBooleanFlagValue(value: []const u8) bool {
        if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false")) return true;
        return false;
    }

    pub fn normalizeFlagName(name: []const u8) []const u8 {
        if (name.len > 2 and name[0] == '-' and name[1] == '-') {
            return name[2..];
        } else if (name.len > 1 and name[0] == '-' and name[1] != '-') {
            return name[1..];
        }
        return name;
    }

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
};

pub const FlagBuilder = struct {
    name: []const u8,
    description: []const u8,
    short_name: ?u8 = null,
    default_value: ?FlagValue = null,
    flag_type: FlagType,
    persistent: bool = false,

    fn init(name: []const u8, description: []const u8, flag_type: FlagType) FlagBuilder {
        return .{
            .name = name,
            .description = description,
            .flag_type = flag_type,
            .persistent = false,
        };
    }

    fn initWithDefaultValue(name: []const u8, description: []const u8, value: FlagValue) FlagBuilder {
        return .{
            .name = name,
            .description = description,
            .flag_type = value.flag_type(),
            .default_value = value,
            .persistent = false,
        };
    }

    pub fn withShortName(self: FlagBuilder, short_name: u8) FlagBuilder {
        var new_self = self;
        new_self.short_name = short_name;
        return new_self;
    }

    pub fn markPersistent(self: FlagBuilder) FlagBuilder {
        var new_self = self;
        new_self.persistent = true;
        return new_self;
    }

    pub fn build(self: FlagBuilder) Flag {
        return Flag.create(self.name, self.short_name, self.description, self.flag_type, self.default_value, self.persistent);
    }
};

pub const ParsedFlag = struct {
    name: []const u8,
    value: FlagValue,

    pub fn init(name: []const u8, value: FlagValue) ParsedFlag {
        return .{ .name = name, .value = value };
    }
};

pub const ParsedFlags = struct {
    flag_by_name: std.StringHashMap(ParsedFlag),

    pub fn init(allocator: std.mem.Allocator) ParsedFlags {
        return .{ .flag_by_name = std.StringHashMap(ParsedFlag).init(allocator) };
    }

    pub fn addFlag(self: *ParsedFlags, flag: ParsedFlag) !void {
        try self.flag_by_name.put(flag.name, flag);
    }

    pub fn getBoolean(self: ParsedFlags, name: []const u8) FlagValueGetError!bool {
        const flag = self.flag_by_name.get(name) orelse return FlagValueGetError.FlagNotFound;
        switch (flag.value) {
            .boolean => return flag.value.boolean,
            else => return FlagValueGetError.FlagTypeMismatch,
        }
    }

    pub fn getInt64(self: ParsedFlags, name: []const u8) FlagValueGetError!i64 {
        const flag = self.flag_by_name.get(name) orelse return FlagValueGetError.FlagNotFound;
        switch (flag.value) {
            .int64 => return flag.value.int64,
            else => return FlagValueGetError.FlagTypeMismatch,
        }
    }

    pub fn getString(self: ParsedFlags, name: []const u8) FlagValueGetError![]const u8 {
        const flag = self.flag_by_name.get(name) orelse return FlagValueGetError.FlagNotFound;
        switch (flag.value) {
            .string => return flag.value.string,
            else => return FlagValueGetError.FlagTypeMismatch,
        }
    }

    pub fn merge(self: *ParsedFlags, other: *const ParsedFlags) !void {
        var other_iterator = other.flag_by_name.valueIterator();
        while (other_iterator.next()) |other_flag| {
            if (self.flag_by_name.contains(other_flag.name)) {
                continue;
            }
            try self.addFlag(other_flag.*);
        }
    }

    pub fn deinit(self: *ParsedFlags) void {
        self.flag_by_name.deinit();
    }
};

test "build a boolean flag with name and description" {
    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean)
        .build();

    try std.testing.expectEqualStrings("verbose", verbose_flag.name);
    try std.testing.expectEqualStrings("Enable verbose output", verbose_flag.description);
    try std.testing.expect(verbose_flag.flag_type == FlagType.boolean);
    try std.testing.expect(verbose_flag.default_value == null);
    try std.testing.expect(verbose_flag.short_name == null);
}

test "build a boolean flag with short name and default value" {
    const verbose_flag = Flag.builder_with_default_value("verbose", "Enable verbose output", FlagValue.type_boolean(false))
        .withShortName('v')
        .build();

    try std.testing.expectEqualStrings("verbose", verbose_flag.name);
    try std.testing.expectEqualStrings("Enable verbose output", verbose_flag.description);
    try std.testing.expectEqual(false, verbose_flag.default_value.?.boolean);
    try std.testing.expectEqual('v', verbose_flag.short_name.?);
}

test "build a int64 flag with name and description" {
    const count_flag = Flag.builder("count", "Count items", FlagType.int64)
        .build();

    try std.testing.expectEqualStrings("count", count_flag.name);
    try std.testing.expectEqualStrings("Count items", count_flag.description);
    try std.testing.expect(count_flag.flag_type == FlagType.int64);
    try std.testing.expect(count_flag.default_value == null);
    try std.testing.expect(count_flag.short_name == null);
}

test "build a int64 flag with short name and default value" {
    const count_flag = Flag.builder_with_default_value("count", "Count items", FlagValue.type_int64(10))
        .withShortName('c')
        .build();

    try std.testing.expectEqualStrings("count", count_flag.name);
    try std.testing.expectEqualStrings("Count items", count_flag.description);

    try std.testing.expectEqual(10, count_flag.default_value.?.int64);
    try std.testing.expectEqual('c', count_flag.short_name.?);
}

test "build a string flag with name and description" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace", FlagType.string)
        .build();

    try std.testing.expectEqualStrings("namespace", namespace_flag.name);
    try std.testing.expectEqualStrings("Define the namespace", namespace_flag.description);
    try std.testing.expect(namespace_flag.default_value == null);
    try std.testing.expect(namespace_flag.short_name == null);
}

test "build a string flag with short name and default value" {
    const namespace_flag = Flag.builder_with_default_value("namespace", "Define the namespace", FlagValue.type_string("default_namespace"))
        .withShortName('n')
        .build();

    try std.testing.expectEqualStrings("namespace", namespace_flag.name);
    try std.testing.expectEqualStrings("Define the namespace", namespace_flag.description);
    try std.testing.expectEqualStrings("default_namespace", namespace_flag.default_value.?.string);
    try std.testing.expect(namespace_flag.flag_type == FlagType.string);
    try std.testing.expectEqual('n', namespace_flag.short_name.?);
}

test "build a persistent flag" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace", FlagType.string)
        .markPersistent()
        .build();

    try std.testing.expect(namespace_flag.persistent);
}

test "build a non-persistent flag" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace", FlagType.string)
        .build();

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
    const namespace_flag = Flag.builder_with_default_value("namespace", "Define the namespace", FlagValue.type_string("default_namespace"))
        .withShortName('n')
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    const namespace_counting_flag = Flag.builder("namespace", "Count namespaces", FlagType.int64)
        .withShortName('n')
        .build();

    try std.testing.expectError(FlagAddError.FlagNameAlreadyExists, flags.addFlag(namespace_counting_flag, &diagnostics));

    const diagnostic_type = diagnostics.diagnostics_type.?.FlagNameAlreadyExists;
    try std.testing.expectEqualStrings("namespace", diagnostic_type.flag_name);
}

test "attempt to add a flag with an existing short name" {
    const namespace_flag = Flag.builder_with_default_value("namespace", "Define the namespace", FlagValue.type_string("default_namespace"))
        .withShortName('n')
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    const namespace_counting_flag = Flag.builder("counter", "Count namespaces", FlagType.int64)
        .withShortName('n')
        .build();

    try std.testing.expectError(FlagAddError.FlagShortNameAlreadyExists, flags.addFlag(namespace_counting_flag, &diagnostics));

    const diagnostic_type = diagnostics.diagnostics_type.?.FlagShortNameAlreadyExists;
    try std.testing.expectEqual('n', diagnostic_type.short_name);
}

test "add a flag and check its existence by name" {
    const namespace_flag = Flag.builder_with_default_value("namespace", "Define the namespace", FlagValue.type_string("default_namespace"))
        .withShortName('n')
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(namespace_flag, &diagnostics);

    try std.testing.expectEqualStrings("namespace", flags.get("namespace").?.name);
}

test "add a flag and check its existence by short name" {
    const namespace_flag = Flag.builder_with_default_value("namespace", "Define the namespace", FlagValue.type_string("default_namespace"))
        .withShortName('n')
        .build();

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
    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean)
        .build();

    var diagnostics: Diagnostics = .{};
    const flag_value = try verbose_flag.toFlagValue("true", &diagnostics);

    try std.testing.expect(flag_value.boolean);
}

test "convert a string to false boolean flag value" {
    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean)
        .build();

    var diagnostics: Diagnostics = .{};
    const flag_value = try verbose_flag.toFlagValue("false", &diagnostics);

    try std.testing.expect(flag_value.boolean == false);
}

test "attempt to convert a string to true boolean flag value" {
    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean)
        .build();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(FlagValueConversionError.InvalidBoolean, verbose_flag.toFlagValue("nothing", &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.InvalidBoolean;
    try std.testing.expectEqualStrings("verbose", diagnostics_type.flag_name);
    try std.testing.expectEqual("nothing", diagnostics_type.value);
}

test "convert a string to int64 flag value" {
    const count_flag = Flag.builder("count", "Count items", FlagType.int64)
        .build();

    var diagnostics: Diagnostics = .{};
    const flag_value = try count_flag.toFlagValue("123", &diagnostics);

    try std.testing.expectEqual(123, flag_value.int64);
}

test "attempt to convert a string to int64 flag value" {
    const count_flag = Flag.builder("count", "Count items", FlagType.int64)
        .build();

    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(FlagValueConversionError.InvalidInteger, count_flag.toFlagValue("nothing", &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.InvalidInteger;
    try std.testing.expectEqualStrings("count", diagnostics_type.flag_name);
    try std.testing.expectEqual("nothing", diagnostics_type.value);
}

test "convert a string to string flag value" {
    const namespace_flag = Flag.builder("namespace", "Define namespace", FlagType.string)
        .build();

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
    try flags.addFlag(Flag.builder_with_default_value("namespace", "Define the namespace", FlagValue.type_string("default_namespace"))
        .withShortName('n')
        .build(), &diagnostics);

    try other_flags.addFlag(Flag.builder("verbose", "Define verbose output", FlagType.boolean).build(), &diagnostics);

    try flags.merge(&other_flags, &diagnostics);

    try std.testing.expectEqualStrings("namespace", flags.get("n").?.name);
    try std.testing.expectEqualStrings("verbose", flags.get("verbose").?.name);
}

test "merge flags containing flags with same name" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = Flags.init(std.testing.allocator);
    defer other_flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(Flag.builder_with_default_value("namespace", "Define the namespace", FlagValue.type_string("default_namespace"))
        .withShortName('n')
        .build(), &diagnostics);

    try other_flags.addFlag(Flag.builder("verbose", "Define verbose output", FlagType.boolean).build(), &diagnostics);
    try other_flags.addFlag(Flag.builder("namespace", "Define namespace", FlagType.string).build(), &diagnostics);

    try flags.merge(&other_flags, &diagnostics);

    try std.testing.expectEqualStrings("namespace", flags.get("n").?.name);
    try std.testing.expectEqualStrings("default_namespace", flags.get("n").?.default_value.?.string);
    try std.testing.expectEqualStrings("verbose", flags.get("verbose").?.name);
}

test "merge flags with conflicting short names" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = Flags.init(std.testing.allocator);
    defer other_flags.deinit();

    var diagnostics: Diagnostics = .{};
    try flags.addFlag(Flag.builder_with_default_value("namespace", "Define the namespace", FlagValue.type_string("default_namespace"))
        .withShortName('n')
        .build(), &diagnostics);

    try other_flags.addFlag(Flag.builder("verbose", "Define verbose output", FlagType.boolean).build(), &diagnostics);
    try other_flags.addFlag(Flag.builder("new", "Create new object", FlagType.string)
        .withShortName('n')
        .build(), &diagnostics);

    try std.testing.expectError(FlagAddError.FlagShortNameMergeConflict, flags.merge(&other_flags, &diagnostics));

    const diagnostics_type = diagnostics.diagnostics_type.?.FlagShortNameMergeConflict;
    try std.testing.expectEqual('n', diagnostics_type.short_name);
    try std.testing.expectEqualStrings("new", diagnostics_type.flag_name);
    try std.testing.expectEqualStrings("namespace", diagnostics_type.conflicting_flag_name);
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

    const timeout_flag = Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(25))
        .build();

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

    const timeout_flag = Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(25))
        .build();

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

    const timeout_flag = Flag.builder_with_default_value("timeout", "Define timeout", FlagValue.type_int64(25))
        .markPersistent()
        .build();

    const verbose_flag = Flag.builder_with_default_value("verbose", "Display verbose output", FlagValue.type_boolean(false))
        .markPersistent()
        .build();

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

test "merge parsed flags containing unique flags" {
    var flags = ParsedFlags.init(std.testing.allocator);
    defer flags.deinit();

    var other_flags = ParsedFlags.init(std.testing.allocator);
    defer other_flags.deinit();

    try flags.addFlag(ParsedFlag.init("namespace", FlagValue.type_string("default_namespace")));
    try other_flags.addFlag(ParsedFlag.init("verbose", FlagValue.type_boolean(false)));

    try flags.merge(&other_flags);

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

    try flags.merge(&other_flags);

    try std.testing.expectEqualStrings("default_namespace", try flags.getString("namespace"));
    try std.testing.expect(try flags.getBoolean("verbose") == false);
}
