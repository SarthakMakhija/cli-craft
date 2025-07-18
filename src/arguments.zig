const std = @import("std");

/// Defines errors that can occur during argument processing.
pub const ArgumentsError = error{
    /// No arguments were provided when required.
    NoArgumentsProvided,
    /// An invalid setup or state was detected for arguments.
    InvalidArgumentsSetup,
};

/// A utility struct for iterating over command-line arguments.
///
/// It can operate either on `std.process.ArgIterator` (for actual command-line arguments)
/// or on a predefined slice of arguments (useful for testing or custom input).
pub const Arguments = struct {
    /// An optional `std.process.ArgIterator` for live command-line arguments.
    argument_iterator: ?std.process.ArgIterator = null,
    /// An optional slice of arguments for predefined input.
    argument_slice: ?[]const []const u8 = null,
    /// The current index when iterating over `argument_slice`.
    index: usize = 0,

    /// Initializes `Arguments` to read from the actual command-line arguments
    /// using `std.process.ArgIterator`.
    pub fn init() Arguments {
        return .{ .argument_iterator = std.process.ArgIterator.init() };
    }

    /// Initializes `Arguments` with a predefined slice of arguments.
    ///
    /// This is particularly useful for testing or when arguments are provided
    /// from a source other than the command line.
    ///
    /// Parameters:
    ///   args: A slice of string slices representing the arguments.
    ///
    /// Returns:
    ///   An `Arguments` instance, or `ArgumentsError.NoArgumentsProvided` if the slice
    ///   is empty.
    pub fn initWithArgs(args: []const []const u8) !Arguments {
        if (args.len == 0) {
            return ArgumentsError.NoArgumentsProvided;
        }
        return .{ .argument_slice = args };
    }

    /// Skips the first argument in the sequence.
    ///
    /// If using `std.process.ArgIterator`, it advances the iterator once.
    /// If using an `argument_slice`, it increments the internal index.
    pub fn skipFirst(self: *Arguments) void {
        if (self.argument_iterator) |*iterator| {
            _ = iterator.next();
        } else if (self.argument_slice) |_| {
            self.index += 1;
        }
    }

    /// Retrieves the next argument in the sequence.
    ///
    /// Returns:
    ///   The next argument as a `[]const u8` slice, or `null` if no more arguments are
    ///   available.
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
