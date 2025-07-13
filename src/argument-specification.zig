const std = @import("std");
const OutputStream = @import("stream.zig").OutputStream;

pub const ArgumentValidationError = error{ ArgumentsNotEqualToZero, ArgumentsLessThanMinimum, ArgumentsGreaterThanMaximum, ArgumentsNotMatchingExpected, ArgumentsNotInEndExclusiveRange, ArgumentsNotInEndInclusiveRange };
pub const ArgumentSpecificationError = error{InvalidRange};

pub const ArgumentSpecification = union(enum) {
    zero: usize,
    minimum: usize,
    maximum: usize,
    exact: usize,
    endExclusive: struct { min: usize, max: usize },
    endInclusive: struct { min: usize, max: usize },

    pub fn mustBeZero() ArgumentSpecification {
        return .{ .zero = 0 };
    }

    pub fn mustBeMinimum(count: usize) ArgumentSpecification {
        return .{ .minimum = count };
    }

    pub fn mustBeMaximum(count: usize) ArgumentSpecification {
        return .{ .maximum = count };
    }

    pub fn mustBeExact(count: usize) ArgumentSpecification {
        return .{ .exact = count };
    }

    pub fn mustBeInEndExclusiveRange(min: usize, max: usize) !ArgumentSpecification {
        if (max <= min) {
            return ArgumentSpecificationError.InvalidRange;
        }
        return .{ .endExclusive = .{ .min = min, .max = max } };
    }

    pub fn mustBeInEndInclusiveRange(min: usize, max: usize) !ArgumentSpecification {
        if (max < min) {
            return ArgumentSpecificationError.InvalidRange;
        }
        return .{ .endInclusive = .{ .min = min, .max = max } };
    }

    pub fn validate(self: ArgumentSpecification, argument_count: usize) !void {
        switch (self) {
            .zero => if (argument_count != 0) {
                return ArgumentValidationError.ArgumentsNotEqualToZero;
            },
            .minimum => |expected_argument_count| if (argument_count < expected_argument_count) {
                return ArgumentValidationError.ArgumentsLessThanMinimum;
            },
            .maximum => |expected_argument_count| if (argument_count > expected_argument_count) {
                return ArgumentValidationError.ArgumentsGreaterThanMaximum;
            },
            .exact => |expected_argument_count| if (argument_count != expected_argument_count) {
                return ArgumentValidationError.ArgumentsNotMatchingExpected;
            },
            .endExclusive => |range| if (argument_count < range.min or argument_count >= range.max) {
                return ArgumentValidationError.ArgumentsNotInEndExclusiveRange;
            },
            .endInclusive => |range| if (argument_count < range.min or argument_count > range.max) {
                return ArgumentValidationError.ArgumentsNotInEndInclusiveRange;
            },
        }
    }

    pub fn print(self: ArgumentSpecification, output_stream: OutputStream, allocator: std.mem.Allocator) !void {
        try output_stream.print("Argument Specification:\n", .{});
        const result: []const u8 = switch (self) {
            .zero => try std.fmt.allocPrint(allocator, "  accepts zero arguments", .{}),
            .minimum => |argument_count| try std.fmt.allocPrint(allocator, "  accepts minimum of {d} argument(s)", .{argument_count}),
            .maximum => |argument_count| try std.fmt.allocPrint(allocator, "  accepts maximum of {d} argument(s)", .{argument_count}),
            .exact => |argument_count| try std.fmt.allocPrint(allocator, "  accepts exactly {d} argument(s)", .{argument_count}),
            .endExclusive => |range| try std.fmt.allocPrint(allocator, "  accepts at least {d} argument(s), but less than {d} argument(s)", .{ range.min, range.max }),
            .endInclusive => |range| try std.fmt.allocPrint(allocator, "  accepts at least {d} argument(s) and at most {d} argument(s)", .{ range.min, range.max }),
        };
        defer allocator.free(result);
        try output_stream.printAll(result);
    }
};

test "arguments are not zero" {
    try std.testing.expectError(ArgumentValidationError.ArgumentsNotEqualToZero, ArgumentSpecification.mustBeZero().validate(5));
}

test "arguments are less than the minimum" {
    try std.testing.expectError(ArgumentValidationError.ArgumentsLessThanMinimum, ArgumentSpecification.mustBeMinimum(10).validate(5));
}

test "arguments are greater than the maximum" {
    try std.testing.expectError(ArgumentValidationError.ArgumentsGreaterThanMaximum, ArgumentSpecification.mustBeMaximum(3).validate(5));
}

test "arguments are not matching the exact" {
    try std.testing.expectError(ArgumentValidationError.ArgumentsNotMatchingExpected, ArgumentSpecification.mustBeExact(3).validate(2));
}

test "arguments are not in end-exclusive range, given argument count is equal to the maximum argument of the range" {
    try std.testing.expectError(ArgumentValidationError.ArgumentsNotInEndExclusiveRange, (try ArgumentSpecification.mustBeInEndExclusiveRange(2, 5)).validate(5));
}

test "arguments are not in end-exclusive range, given argument count is less than the minimum argument of the range" {
    try std.testing.expectError(ArgumentValidationError.ArgumentsNotInEndExclusiveRange, (try ArgumentSpecification.mustBeInEndExclusiveRange(2, 5)).validate(1));
}

test "arguments are not in end-inclusive range, given argument count is greater than the maximum argument of the range" {
    try std.testing.expectError(ArgumentValidationError.ArgumentsNotInEndInclusiveRange, (try ArgumentSpecification.mustBeInEndInclusiveRange(2, 5)).validate(6));
}

test "arguments are not in end-inclusive range, given argument count is less than the minimum argument of the range" {
    try std.testing.expectError(ArgumentValidationError.ArgumentsNotInEndInclusiveRange, (try ArgumentSpecification.mustBeInEndInclusiveRange(2, 5)).validate(1));
}

test "invalid argument range for end exclusive range 1" {
    try std.testing.expectError(ArgumentSpecificationError.InvalidRange, ArgumentSpecification.mustBeInEndExclusiveRange(2, 1));
}

test "invalid argument range for end exclusive range 2" {
    try std.testing.expectError(ArgumentSpecificationError.InvalidRange, ArgumentSpecification.mustBeInEndExclusiveRange(2, 2));
}

test "invalid argument range for end inclusive range" {
    try std.testing.expectError(ArgumentSpecificationError.InvalidRange, ArgumentSpecification.mustBeInEndInclusiveRange(2, 1));
}

test "print argument specification with zero arguments" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try ArgumentSpecification.mustBeZero().print(output_stream, std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "accepts zero arguments").? > 0);
}

test "print argument specification with minimum arguments" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try ArgumentSpecification.mustBeMinimum(2).print(output_stream, std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "accepts minimum of 2 argument(s)").? > 0);
}

test "print argument specification with maximum arguments" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try ArgumentSpecification.mustBeMaximum(3).print(output_stream, std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "accepts maximum of 3 argument(s)").? > 0);
}

test "print argument specification with exact arguments" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try ArgumentSpecification.mustBeExact(5).print(output_stream, std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "accepts exactly 5 argument(s)").? > 0);
}

test "print argument specification with arguments in end exclusive range" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try (try ArgumentSpecification.mustBeInEndExclusiveRange(3, 8)).print(output_stream, std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "accepts at least 3 argument(s), but less than 8 argument(s)").? > 0);
}

test "print argument specification with arguments in end inclusive range" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const writer = buffer.writer().any();

    const output_stream = OutputStream.initStdErrWriter(writer);
    try (try ArgumentSpecification.mustBeInEndInclusiveRange(3, 8)).print(output_stream, std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "accepts at least 3 argument(s) and at most 8 argument(s)").? > 0);
}
