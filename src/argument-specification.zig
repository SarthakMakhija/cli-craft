pub const ArgumentSpecificationError = error{
    ArgumentsNotEqualToZero,
    ArgumentsLessThanMinimum,
    ArgumentsGreaterThanMaximum,
    ArgumentsNotMatchingExpected,
    ArgumentsNotInEndExclusiveRange,
    ArgumentsNotInEndInclusiveRange,
};

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

    pub fn mustBeInEndExclusiveRange(min: usize, max: usize) ArgumentSpecification {
        return .{ .endExclusive = .{ .min = min, .max = max } };
    }

    pub fn mustBeInEndInclusiveRange(min: usize, max: usize) ArgumentSpecification {
        return .{ .endInclusive = .{ .min = min, .max = max } };
    }

    pub fn validate(self: ArgumentSpecification, argument_count: usize) !void {
        switch (self) {
            .zero => if (argument_count != 0) {
                return ArgumentSpecificationError.ArgumentsNotEqualToZero;
            },
            .minimum => |expected_argument_count| if (argument_count < expected_argument_count) {
                return ArgumentSpecificationError.ArgumentsLessThanMinimum;
            },
            .maximum => |expected_argument_count| if (argument_count > expected_argument_count) {
                return ArgumentSpecificationError.ArgumentsGreaterThanMaximum;
            },
            .exact => |expected_argument_count| if (argument_count != expected_argument_count) {
                return ArgumentSpecificationError.ArgumentsNotMatchingExpected;
            },
            .endExclusive => |range| if (argument_count < range.min or argument_count >= range.max) {
                return ArgumentSpecificationError.ArgumentsNotInEndExclusiveRange;
            },
            .endInclusive => |range| if (argument_count < range.min or argument_count > range.max) {
                return ArgumentSpecificationError.ArgumentsNotInEndInclusiveRange;
            },
        }
    }
};

const std = @import("std");

test "arguments are not zero" {
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsNotEqualToZero, ArgumentSpecification.mustBeZero().validate(5));
}

test "arguments are less than the minimum" {
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsLessThanMinimum, ArgumentSpecification.mustBeMinimum(10).validate(5));
}

test "arguments are greater than the maximum" {
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsGreaterThanMaximum, ArgumentSpecification.mustBeMaximum(3).validate(5));
}

test "arguments are not matching the exact" {
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsNotMatchingExpected, ArgumentSpecification.mustBeExact(3).validate(2));
}

test "arguments are not in end-exclusive range, given argument count is equal to the maximum argument of the range" {
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsNotInEndExclusiveRange, ArgumentSpecification.mustBeInEndExclusiveRange(2, 5).validate(5));
}

test "arguments are not in end-exclusive range, given argument count is less than the minimum argument of the range" {
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsNotInEndExclusiveRange, ArgumentSpecification.mustBeInEndExclusiveRange(2, 5).validate(1));
}

test "arguments are not in end-inclusive range, given argument count is greater than the maximum argument of the range" {
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsNotInEndInclusiveRange, ArgumentSpecification.mustBeInEndInclusiveRange(2, 5).validate(6));
}

test "arguments are not in end-inclusive range, given argument count is less than the minimum argument of the range" {
    try std.testing.expectError(ArgumentSpecificationError.ArgumentsNotInEndInclusiveRange, ArgumentSpecification.mustBeInEndInclusiveRange(2, 5).validate(1));
}
