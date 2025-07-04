const std = @import("std");

pub const FlagValue = union(enum) {
    boolean: bool,
    int64: i64,
    string: []const u8,
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
        .withDefaultValue(FlagValue.boolean(false))
        .build();

    try std.testing.expectEqualStrings("verbose", verbose_flag.name);
    try std.testing.expectEqualStrings("Enable verbose output", verbose_flag.description);
    try std.testing.expectEqual(false, verbose_flag.default_value.?);
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
        .withDefaultValue(FlagValue.int64(10))
        .wothShortName('c')
        .build();

    try std.testing.expectEqualStrings("count", count_flag.name);
    try std.testing.expectEqualStrings("Count items", count_flag.description);
    try std.testing.expectEqual(false, count_flag.default_value.?);
    try std.testing.expectEqual('v', count_flag.short_name.?);
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
        .withDefaultValue(FlagValue.string("default_namespace"))
        .build();

    try std.testing.expectEqualStrings("namespace", namespace_flag.name);
    try std.testing.expectEqualStrings("Define the namespace", namespace_flag.description);
    try std.testing.expectEqualStrings("default_namespace", namespace_flag.default_value.?);
    try std.testing.expectEqual('n', namespace_flag.short_name.?);
}
