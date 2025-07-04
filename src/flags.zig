const std = @import("std");

pub const FlagAddError = error{
    FlagNameAlreadyExists,
    FlagShortNameAlreadyExists,
};

pub const Flags = struct {
    flags: std.StringHashMap(Flag),
    short_name_to_long_name: std.AutoHashMap(u8, []const u8),

    pub fn init(allocator: std.mem.Allocator) Flags {
        return .{
            .flags = std.StringHashMap(Flag).init(allocator),
            .short_name_to_long_name = std.AutoHashMap(u8, []const u8).init(allocator),
        };
    }

    pub fn addFlag(self: *Flags, flag: Flag) !void {
        if (self.flags.contains(flag.name)) {
            return FlagAddError.FlagNameAlreadyExists;
        }
        if (flag.short_name) |short_name| {
            if (self.short_name_to_long_name.contains(short_name)) {
                return FlagAddError.FlagShortNameAlreadyExists;
            }
        }

        try self.flags.put(flag.name, flag);
        if (flag.short_name) |short_name| {
            try self.short_name_to_long_name.put(short_name, flag.name);
        }
    }

    pub fn contains(self: *Flags, flag_name: []const u8) bool {
        return self.flags.contains(flag_name) or
            (flag_name.len > 0 and self.short_name_to_long_name.contains(flag_name[0]));
    }

    pub fn deinit(self: *Flags) void {
        self.flags.deinit();
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

    pub fn looksLikeFlagName(name: []const u8) bool {
        return (name.len == 2 and name[0] == '-' and name[1] != '-') or
            (name.len > 2 and name[0] == '-' and name[1] == '-');
    }

    pub fn builder(name: []const u8, description: []const u8, flag_type: FlagType) FlagBuilder {
        return FlagBuilder.init(name, description, flag_type);
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
        };
    }

    pub fn withShortName(self: FlagBuilder, short_name: u8) FlagBuilder {
        var new_self = self;
        new_self.short_name = short_name;
        return new_self;
    }

    pub fn withDefaultValue(self: FlagBuilder, value: FlagValue) FlagBuilder {
        var new_self = self;
        new_self.default_value = value;
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
    const verbose_flag = Flag.builder("verbose", "Enable verbose output", FlagType.boolean)
        .withShortName('v')
        .withDefaultValue(FlagValue.type_boolean(false))
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
    const count_flag = Flag.builder("count", "Count items", FlagType.int64)
        .withDefaultValue(FlagValue.type_int64(10))
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
    const namespace_flag = Flag.builder("namespace", "Define the namespace", FlagType.string)
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
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

test "attempt to add a flag with an existing name" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace", FlagType.string)
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(namespace_flag);

    const namespace_counting_flag = Flag.builder("namespace", "Count namespaces", FlagType.int64)
        .withShortName('n')
        .build();

    try std.testing.expectError(FlagAddError.FlagNameAlreadyExists, flags.addFlag(namespace_counting_flag));
}

test "attempt to add a flag with an existing short name" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace", FlagType.string)
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(namespace_flag);

    const namespace_counting_flag = Flag.builder("counter", "Count namespaces", FlagType.int64)
        .withShortName('n')
        .build();

    try std.testing.expectError(FlagAddError.FlagShortNameAlreadyExists, flags.addFlag(namespace_counting_flag));
}

test "add a flag and check its existence by name" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace", FlagType.string)
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(namespace_flag);

    try std.testing.expect(flags.contains("namespace"));
}

test "add a flag and check its existence by short name" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace", FlagType.string)
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(namespace_flag);

    try std.testing.expect(flags.contains("n"));
}

test "check the existence of a non-existing flag by name" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try std.testing.expect(flags.contains("verbose") == false);
}

test "check the existence of a non-existing flag by short name" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try std.testing.expect(flags.contains("v") == false);
}
