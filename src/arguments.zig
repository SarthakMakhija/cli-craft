const std = @import("std");

const ArgumentsError = error{
    NoArgumentsProvided,
};

const Arguments = struct {
    argument_iterator: ?std.process.ArgIterator = null,
    argument_slice: ?[]const [:0]const u8 = null,
    index: usize = 0,

    pub fn init() Arguments {
        return .{ .argument_iterator = std.process.ArgIterator.init() };
    }

    pub fn initWithArgs(args: []const [:0]const u8) !Arguments {
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

    pub fn next(self: *Arguments) ?([:0]const u8) {
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
};

test "next argument from iterator" {
    var arguments = try Arguments.initWithArgs(&[_][:0]const u8{"kubectl"});
    const argument = arguments.next();

    try std.testing.expect(argument != null);
    try std.testing.expectEqualStrings("kubectl", argument.?);
}

test "next argument after skipping the first argument" {
    var arguments = try Arguments.initWithArgs(&[_][:0]const u8{ "kubectl", "get" });
    arguments.skipFirst();

    const argument = arguments.next();

    try std.testing.expect(argument != null);
    try std.testing.expectEqualStrings("get", argument.?);
}

test "attempt to get the next argument after skipping the first argument" {
    var arguments = try Arguments.initWithArgs(&[_][:0]const u8{"kubectl"});
    arguments.skipFirst();

    const argument = arguments.next();

    try std.testing.expect(argument == null);
}

test "attempt to get the next argument after consuming the only argument" {
    var arguments = try Arguments.initWithArgs(&[_][:0]const u8{"kubectl"});

    _ = arguments.next();
    const argument = arguments.next();

    try std.testing.expect(argument == null);
}

test "attempt to skip the first argument when there is no argument" {
    _ = Arguments.initWithArgs(&[_][:0]const u8{}) catch |err| {
        try std.testing.expectEqual(ArgumentsError.NoArgumentsProvided, err);
    };
}
