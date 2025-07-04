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

pub const FlagValue = union(enum) {
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
    default_value: ?FlagValue,

    fn create(
        name: []const u8,
        short_name: ?u8,
        description: []const u8,
        default_value: ?FlagValue,
    ) Flag {
        return .{
            .name = name,
            .short_name = short_name,
            .description = description,
            .default_value = default_value,
        };
    }

    pub fn builder(name: []const u8, description: []const u8) FlagBuilder {
        return FlagBuilder.init(name, description);
    }
};

pub const FlagBuilder = struct {
    name: []const u8,
    description: []const u8,
    short_name: ?u8 = null,
    default_value: ?FlagValue = null,

    fn init(name: []const u8, description: []const u8) FlagBuilder {
        return .{
            .name = name,
            .description = description,
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

    pub fn build(self: FlagBuilder) Flag {
        return Flag.create(
            self.name,
            self.short_name,
            self.description,
            self.default_value,
        );
    }
};

test "build a boolean flag with name and description" {
    const verbose_flag = Flag.builder("verbose", "Enable verbose output")
        .build();

    try std.testing.expectEqualStrings("verbose", verbose_flag.name);
    try std.testing.expectEqualStrings("Enable verbose output", verbose_flag.description);
    try std.testing.expect(verbose_flag.default_value == null);
    try std.testing.expect(verbose_flag.short_name == null);
}

test "build a boolean flag with short name and default value" {
    const verbose_flag = Flag.builder("verbose", "Enable verbose output")
        .withShortName('v')
        .withDefaultValue(FlagValue.type_boolean(false))
        .build();

    try std.testing.expectEqualStrings("verbose", verbose_flag.name);
    try std.testing.expectEqualStrings("Enable verbose output", verbose_flag.description);
    try std.testing.expectEqual(false, verbose_flag.default_value.?.boolean);
    try std.testing.expectEqual('v', verbose_flag.short_name.?);
}

test "build a int64 flag with name and description" {
    const count_flag = Flag.builder("count", "Count items")
        .build();

    try std.testing.expectEqualStrings("count", count_flag.name);
    try std.testing.expectEqualStrings("Count items", count_flag.description);
    try std.testing.expect(count_flag.default_value == null);
    try std.testing.expect(count_flag.short_name == null);
}

test "build a int64 flag with short name and default value" {
    const count_flag = Flag.builder("count", "Count items")
        .withDefaultValue(FlagValue.type_int64(10))
        .withShortName('c')
        .build();

    try std.testing.expectEqualStrings("count", count_flag.name);
    try std.testing.expectEqualStrings("Count items", count_flag.description);

    try std.testing.expectEqual(10, count_flag.default_value.?.int64);
    try std.testing.expectEqual('c', count_flag.short_name.?);
}

test "build a string flag with name and description" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace")
        .build();

    try std.testing.expectEqualStrings("namespace", namespace_flag.name);
    try std.testing.expectEqualStrings("Define the namespace", namespace_flag.description);
    try std.testing.expect(namespace_flag.default_value == null);
    try std.testing.expect(namespace_flag.short_name == null);
}

test "build a string flag with short name and default value" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace")
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
        .build();

    try std.testing.expectEqualStrings("namespace", namespace_flag.name);
    try std.testing.expectEqualStrings("Define the namespace", namespace_flag.description);
    try std.testing.expectEqualStrings("default_namespace", namespace_flag.default_value.?.string);
    try std.testing.expectEqual('n', namespace_flag.short_name.?);
}

test "attempt to add a flag with an existing name" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace")
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(namespace_flag);

    const namespace_counting_flag = Flag.builder("namespace", "Count namespaces")
        .withShortName('n')
        .build();

    try std.testing.expectError(FlagAddError.FlagNameAlreadyExists, flags.addFlag(namespace_counting_flag));
}

test "attempt to add a flag with an existing short name" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace")
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(namespace_flag);

    const namespace_counting_flag = Flag.builder("counter", "Count namespaces")
        .withShortName('n')
        .build();

    try std.testing.expectError(FlagAddError.FlagShortNameAlreadyExists, flags.addFlag(namespace_counting_flag));
}

test "add a flag and check its existence by name" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace")
        .withShortName('n')
        .withDefaultValue(FlagValue.type_string("default_namespace"))
        .build();

    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(namespace_flag);

    try std.testing.expect(flags.contains("namespace"));
}

test "add a flag and check its existence by short name" {
    const namespace_flag = Flag.builder("namespace", "Define the namespace")
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
