const std = @import("std");
const OutputStream = @import("stream.zig").OutputStream;

pub const ArgumentValidationError = error{ ArgumentsNotEqualToZero, ArgumentsLessThanMinimum, ArgumentsGreaterThanMaximum, ArgumentsNotMatchingExpected, ArgumentsNotInEndExclusiveRange, ArgumentsNotInEndInclusiveRange };
pub const ArgumentSpecificationError = error{InvalidRange};

const Diagnostics = @import("diagnostics.zig").Diagnostics;

/// Defines the rules for a command's positional arguments.
/// This union allows specifying various constraints on the number of arguments a command expects.
pub const ArgumentSpecification = union(enum) {
    /// Specifies that the command accepts exactly zero arguments.
    zero: usize,
    /// Specifies that the command accepts a minimum number of arguments.
    minimum: usize,
    /// Specifies that the command accepts a maximum number of arguments.
    maximum: usize,
    /// Specifies that the command accepts an exact number of arguments.
    exact: usize,
    /// Specifies a range of arguments where the minimum is inclusive and the maximum is exclusive.
    /// (e.g., `min` arguments up to, but not including, `max` arguments).
    endExclusive: struct { min: usize, max: usize },
    /// Specifies a range of arguments where both the minimum and maximum are inclusive.
    /// (e.g., `min` arguments up to and including `max` arguments).
    endInclusive: struct { min: usize, max: usize },

    /// Creates an `ArgumentSpecification` that requires exactly zero arguments.
    pub fn mustBeZero() ArgumentSpecification {
        return .{ .zero = 0 };
    }

    /// Creates an `ArgumentSpecification` that requires at least a specified minimum number of arguments.
    ///
    /// Parameters:
    ///   count: The minimum number of arguments required.
    pub fn mustBeMinimum(count: usize) ArgumentSpecification {
        return .{ .minimum = count };
    }

    /// Creates an `ArgumentSpecification` that accepts at most a specified maximum number of arguments.
    ///
    /// Parameters:
    ///   count: The maximum number of arguments allowed.
    pub fn mustBeMaximum(count: usize) ArgumentSpecification {
        return .{ .maximum = count };
    }

    /// Creates an `ArgumentSpecification` that requires precisely a specified number of arguments.
    ///
    /// Parameters:
    ///   count: The exact number of arguments required.
    pub fn mustBeExact(count: usize) ArgumentSpecification {
        return .{ .exact = count };
    }

    /// Creates an `ArgumentSpecification` for a range where the minimum is inclusive and the maximum is exclusive.
    ///
    /// Parameters:
    ///   min: The minimum number of arguments (inclusive).
    ///   max: The maximum number of arguments (exclusive).
    ///
    /// Returns:
    ///   An `ArgumentSpecification` or an ArgumentSpecificationError if `max` is not greater than `min`.
    pub fn mustBeInEndExclusiveRange(min: usize, max: usize) !ArgumentSpecification {
        if (max <= min) {
            return ArgumentSpecificationError.InvalidRange;
        }
        return .{ .endExclusive = .{ .min = min, .max = max } };
    }

    /// Creates an `ArgumentSpecification` for a range where both the minimum and maximum are inclusive.
    ///
    /// Parameters:
    ///   min: The minimum number of arguments (inclusive).
    ///   max: The maximum number of arguments (inclusive).
    ///
    /// Returns:
    ///   An `ArgumentSpecification` or an ArgumentSpecificationError if `max` is less than `min`.
    pub fn mustBeInEndInclusiveRange(min: usize, max: usize) !ArgumentSpecification {
        if (max < min) {
            return ArgumentSpecificationError.InvalidRange;
        }
        return .{ .endInclusive = .{ .min = min, .max = max } };
    }

    /// Validates if the given `argument_count` adheres to this `ArgumentSpecification`.
    ///
    /// Parameters:
    ///   argument_count: The actual number of arguments provided.
    ///   diagnostics: A pointer to the `Diagnostics` instance for reporting validation errors.
    ///
    /// Returns:
    ///   `void` on success, or an error if the argument count does not meet the specification.
    pub fn validate(
        self: ArgumentSpecification,
        argument_count: usize,
        diagnostics: *Diagnostics,
    ) !void {
        switch (self) {
            .zero => if (argument_count != 0) {
                return diagnostics.reportAndFail(.{ .ArgumentsNotEqualToZero = .{
                    .actual_arguments = argument_count,
                } });
            },
            .minimum => |expected_argument_count| if (argument_count < expected_argument_count) {
                return diagnostics.reportAndFail(.{ .ArgumentsLessThanMinimum = .{
                    .expected_arguments = expected_argument_count,
                    .actual_arguments = argument_count,
                } });
            },
            .maximum => |expected_argument_count| if (argument_count > expected_argument_count) {
                return diagnostics.reportAndFail(.{ .ArgumentsGreaterThanMaximum = .{
                    .expected_arguments = expected_argument_count,
                    .actual_arguments = argument_count,
                } });
            },
            .exact => |expected_argument_count| if (argument_count != expected_argument_count) {
                return diagnostics.reportAndFail(.{ .ArgumentsNotMatchingExpected = .{
                    .expected_arguments = expected_argument_count,
                    .actual_arguments = argument_count,
                } });
            },
            .endExclusive => |range| if (argument_count < range.min or argument_count >= range.max) {
                return diagnostics.reportAndFail(.{ .ArgumentsNotInEndExclusiveRange = .{
                    .minimum_arguments = range.min,
                    .maximum_arguments = range.max,
                    .actual_arguments = argument_count,
                } });
            },
            .endInclusive => |range| if (argument_count < range.min or argument_count > range.max) {
                return diagnostics.reportAndFail(.{ .ArgumentsNotInEndInclusiveRange = .{
                    .minimum_arguments = range.min,
                    .maximum_arguments = range.max,
                    .actual_arguments = argument_count,
                } });
            },
        }
    }

    /// Prints a human-readable description of this argument specification to the output stream.
    ///
    /// Parameters:
    ///   output_stream: The `OutputStream` to write the description to.
    ///   allocator: The allocator to use for temporary string formatting.
    pub fn print(self: ArgumentSpecification, output_stream: OutputStream, allocator: std.mem.Allocator) !void {
        try output_stream.print("Argument Specification:\n", .{});
        const result: []const u8 = switch (self) {
            .zero => try std.fmt.allocPrint(allocator, "  accepts zero arguments", .{}),
            .minimum => |argument_count| try std.fmt.allocPrint(
                allocator,
                "  accepts minimum of {d} argument(s)",
                .{argument_count},
            ),
            .maximum => |argument_count| try std.fmt.allocPrint(
                allocator,
                "  accepts maximum of {d} argument(s)",
                .{argument_count},
            ),
            .exact => |argument_count| try std.fmt.allocPrint(
                allocator,
                "  accepts exactly {d} argument(s)",
                .{argument_count},
            ),
            .endExclusive => |range| try std.fmt.allocPrint(
                allocator,
                "  accepts at least {d} argument(s), but less than {d} argument(s)",
                .{ range.min, range.max },
            ),
            .endInclusive => |range| try std.fmt.allocPrint(
                allocator,
                "  accepts at least {d} argument(s) and at most {d} argument(s)",
                .{ range.min, range.max },
            ),
        };
        defer allocator.free(result);
        try output_stream.printAll(result);
    }
};

test "arguments are not zero" {
    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(
        ArgumentValidationError.ArgumentsNotEqualToZero,
        ArgumentSpecification.mustBeZero().validate(5, &diagnostics),
    );
    try std.testing.expectEqual(5, diagnostics.diagnostics_type.?.ArgumentsNotEqualToZero.actual_arguments);
}

test "arguments are less than the minimum" {
    var diagnostics: Diagnostics = .{};

    try std.testing.expectError(
        ArgumentValidationError.ArgumentsLessThanMinimum,
        ArgumentSpecification.mustBeMinimum(10).validate(5, &diagnostics),
    );

    try std.testing.expectEqual(10, diagnostics.diagnostics_type.?.ArgumentsLessThanMinimum.expected_arguments);
    try std.testing.expectEqual(5, diagnostics.diagnostics_type.?.ArgumentsLessThanMinimum.actual_arguments);
}

test "arguments are greater than the maximum" {
    var diagnostics: Diagnostics = .{};

    try std.testing.expectError(
        ArgumentValidationError.ArgumentsGreaterThanMaximum,
        ArgumentSpecification.mustBeMaximum(3).validate(5, &diagnostics),
    );

    try std.testing.expectEqual(3, diagnostics.diagnostics_type.?.ArgumentsGreaterThanMaximum.expected_arguments);
    try std.testing.expectEqual(5, diagnostics.diagnostics_type.?.ArgumentsGreaterThanMaximum.actual_arguments);
}

test "arguments are not matching the exact" {
    var diagnostics: Diagnostics = .{};

    try std.testing.expectError(
        ArgumentValidationError.ArgumentsNotMatchingExpected,
        ArgumentSpecification.mustBeExact(3).validate(2, &diagnostics),
    );

    try std.testing.expectEqual(3, diagnostics.diagnostics_type.?.ArgumentsNotMatchingExpected.expected_arguments);
    try std.testing.expectEqual(2, diagnostics.diagnostics_type.?.ArgumentsNotMatchingExpected.actual_arguments);
}

test "arguments are not in end-exclusive range, given argument count is equal to the maximum argument of the range" {
    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(
        ArgumentValidationError.ArgumentsNotInEndExclusiveRange,
        (try ArgumentSpecification.mustBeInEndExclusiveRange(2, 5)).validate(5, &diagnostics),
    );

    try std.testing.expectEqual(2, diagnostics.diagnostics_type.?.ArgumentsNotInEndExclusiveRange.minimum_arguments);
    try std.testing.expectEqual(5, diagnostics.diagnostics_type.?.ArgumentsNotInEndExclusiveRange.maximum_arguments);
    try std.testing.expectEqual(5, diagnostics.diagnostics_type.?.ArgumentsNotInEndExclusiveRange.actual_arguments);
}

test "arguments are not in end-exclusive range, given argument count is less than the minimum argument of the range" {
    var diagnostics: Diagnostics = .{};

    try std.testing.expectError(
        ArgumentValidationError.ArgumentsNotInEndExclusiveRange,
        (try ArgumentSpecification.mustBeInEndExclusiveRange(2, 5)).validate(1, &diagnostics),
    );
    try std.testing.expectEqual(2, diagnostics.diagnostics_type.?.ArgumentsNotInEndExclusiveRange.minimum_arguments);
    try std.testing.expectEqual(5, diagnostics.diagnostics_type.?.ArgumentsNotInEndExclusiveRange.maximum_arguments);
    try std.testing.expectEqual(1, diagnostics.diagnostics_type.?.ArgumentsNotInEndExclusiveRange.actual_arguments);
}

test "arguments are not in end-inclusive range, given argument count is greater than the maximum argument of the range" {
    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(
        ArgumentValidationError.ArgumentsNotInEndInclusiveRange,
        (try ArgumentSpecification.mustBeInEndInclusiveRange(2, 5)).validate(6, &diagnostics),
    );
    try std.testing.expectEqual(2, diagnostics.diagnostics_type.?.ArgumentsNotInEndInclusiveRange.minimum_arguments);
    try std.testing.expectEqual(5, diagnostics.diagnostics_type.?.ArgumentsNotInEndInclusiveRange.maximum_arguments);
    try std.testing.expectEqual(6, diagnostics.diagnostics_type.?.ArgumentsNotInEndInclusiveRange.actual_arguments);
}

test "arguments are not in end-inclusive range, given argument count is less than the minimum argument of the range" {
    var diagnostics: Diagnostics = .{};
    try std.testing.expectError(
        ArgumentValidationError.ArgumentsNotInEndInclusiveRange,
        (try ArgumentSpecification.mustBeInEndInclusiveRange(2, 5)).validate(1, &diagnostics),
    );

    try std.testing.expectEqual(2, diagnostics.diagnostics_type.?.ArgumentsNotInEndInclusiveRange.minimum_arguments);
    try std.testing.expectEqual(5, diagnostics.diagnostics_type.?.ArgumentsNotInEndInclusiveRange.maximum_arguments);
    try std.testing.expectEqual(1, diagnostics.diagnostics_type.?.ArgumentsNotInEndInclusiveRange.actual_arguments);
}

test "invalid argument range for end exclusive range 1" {
    try std.testing.expectError(
        ArgumentSpecificationError.InvalidRange,
        ArgumentSpecification.mustBeInEndExclusiveRange(2, 1),
    );
}

test "invalid argument range for end exclusive range 2" {
    try std.testing.expectError(
        ArgumentSpecificationError.InvalidRange,
        ArgumentSpecification.mustBeInEndExclusiveRange(2, 2),
    );
}

test "invalid argument range for end inclusive range" {
    try std.testing.expectError(
        ArgumentSpecificationError.InvalidRange,
        ArgumentSpecification.mustBeInEndInclusiveRange(2, 1),
    );
}

test "print argument specification with zero arguments" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try ArgumentSpecification.mustBeZero().print(
        output_stream,
        std.testing.allocator,
    );

    try std.testing.expect(
        std.mem.indexOf(u8, buffer.items, "accepts zero arguments").? > 0,
    );
}

test "print argument specification with minimum arguments" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try ArgumentSpecification.mustBeMinimum(2).print(
        output_stream,
        std.testing.allocator,
    );

    try std.testing.expect(
        std.mem.indexOf(u8, buffer.items, "accepts minimum of 2 argument(s)").? > 0,
    );
}

test "print argument specification with maximum arguments" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try ArgumentSpecification.mustBeMaximum(3).print(
        output_stream,
        std.testing.allocator,
    );

    try std.testing.expect(
        std.mem.indexOf(u8, buffer.items, "accepts maximum of 3 argument(s)").? > 0,
    );
}

test "print argument specification with exact arguments" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try ArgumentSpecification.mustBeExact(5).print(
        output_stream,
        std.testing.allocator,
    );

    try std.testing.expect(
        std.mem.indexOf(u8, buffer.items, "accepts exactly 5 argument(s)").? > 0,
    );
}

test "print argument specification with arguments in end exclusive range" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try (try ArgumentSpecification.mustBeInEndExclusiveRange(3, 8)).print(
        output_stream,
        std.testing.allocator,
    );

    try std.testing.expect(
        std.mem.indexOf(u8, buffer.items, "accepts at least 3 argument(s), but less than 8 argument(s)").? > 0,
    );
}

test "print argument specification with arguments in end inclusive range" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try (try ArgumentSpecification.mustBeInEndInclusiveRange(3, 8)).print(
        output_stream,
        std.testing.allocator,
    );

    try std.testing.expect(
        std.mem.indexOf(u8, buffer.items, "accepts at least 3 argument(s) and at most 8 argument(s)").? > 0,
    );
}
