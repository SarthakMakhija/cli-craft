const std = @import("std");

const ArgumentsError = error{
    NoArgumentsProvided,
    InvalidArgumentsSetup,
};

pub const Arguments = struct {
    argument_iterator: ?std.process.ArgIterator = null,
    argument_slice: ?[]const []const u8 = null,
    index: usize = 0,

    pub fn init() Arguments {
        return .{ .argument_iterator = std.process.ArgIterator.init() };
    }

    pub fn initWithArgs(args: []const []const u8) !Arguments {
        if (args.len == 0) {
            return ArgumentsError.NoArgumentsProvided;
        }
        return .{ .argument_slice = args };
    }

    pub fn skipFirst(self: *Arguments) void {
        if (self.argument_iterator) |*iterator| {
            _ = iterator.next();
        } else if (self.argument_slice) |arguments| {
            self.argument_slice = arguments[1..];
        }
    }

    pub fn next(self: *Arguments) ?([]const u8) {
        if (self.argument_iterator) |*iterator| {
            return iterator.next();
        } else if (self.argument_slice) |arguments| {
            if (self.index < arguments.len) {
                const argument = arguments[self.index];
                self.index += 1;
                return argument;
            } else {
                return null;
            }
        } else {
            unreachable;
        }
    }

    pub fn all(self: *Arguments, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        if (self.argument_iterator) |*iterator| {
            var collector = std.ArrayList([]const u8).init(allocator);
            while (iterator.next()) |argument| {
                try collector.append(argument);
            }
            return collector;
        } else if (self.argument_slice) |arguments| {
            var collector = std.ArrayList([]const u8).init(allocator);
            for (arguments) |argument| {
                try collector.append(argument);
            }
            return collector;
        } else {
            return ArgumentsError.InvalidArgumentsSetup;
        }
    }
};

test "next argument from iterator" {
    var arguments = try Arguments.initWithArgs(&[_][]const u8{"kubectl"});
    const argument = arguments.next();

    try std.testing.expect(argument != null);
    try std.testing.expectEqualStrings("kubectl", argument.?);
}

test "next argument after skipping the first argument" {
    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get" });
    arguments.skipFirst();

    const argument = arguments.next();

    try std.testing.expect(argument != null);
    try std.testing.expectEqualStrings("get", argument.?);
}

test "attempt to get the next argument after skipping the first argument" {
    var arguments = try Arguments.initWithArgs(&[_][]const u8{"kubectl"});
    arguments.skipFirst();

    const argument = arguments.next();

    try std.testing.expect(argument == null);
}

test "attempt to get the next argument after consuming the only argument" {
    var arguments = try Arguments.initWithArgs(&[_][]const u8{"kubectl"});

    _ = arguments.next();
    const argument = arguments.next();

    try std.testing.expect(argument == null);
}

test "attempt to skip the first argument when there is no argument" {
    try std.testing.expectError(ArgumentsError.NoArgumentsProvided, Arguments.initWithArgs(&[_][:0]const u8{}));
}

test "collect all arguments from iterator (1)" {
    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "kubectl", "get", "pods" });

    const collector = try arguments.all(std.testing.allocator);
    defer collector.deinit();

    try std.testing.expect(collector.items.len == 3);
    try std.testing.expectEqualStrings("kubectl", collector.items[0]);
    try std.testing.expectEqualStrings("get", collector.items[1]);
    try std.testing.expectEqualStrings("pods", collector.items[2]);
}

test "collect all arguments from iterator (2)" {
    var arguments = try Arguments.initWithArgs(&[_][]const u8{ "add", "2", "5" });

    const collector = try arguments.all(std.testing.allocator);
    defer collector.deinit();

    try std.testing.expect(collector.items.len == 3);
    try std.testing.expectEqualStrings("add", collector.items[0]);
    try std.testing.expectEqualStrings("2", collector.items[1]);
    try std.testing.expectEqualStrings("5", collector.items[2]);
}
