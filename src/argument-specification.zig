const ArgumentSpecificationError = error{
    ArgumentsNotEqualToZero,
    ArgumentsLessThanMinimum,
    ArgumentsGreaterThanMaximum,
    ArgumentsNotMatchingExpected,
    ArgumentsNotInEndExclusiveRange,
    ArgumentsNotInEndInclusiveRange,
};

const ArgumentSpecification = union(enum) {
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
    ArgumentSpecification.mustBeZero().validate(5) catch |err| {
        try std.testing.expectEqual(ArgumentSpecificationError.ArgumentsNotEqualToZero, err);
    };
}

test "arguments are less than the minimum" {
    ArgumentSpecification.mustBeMinimum(10).validate(5) catch |err| {
        try std.testing.expectEqual(ArgumentSpecificationError.ArgumentsLessThanMinimum, err);
    };
}

test "arguments are greater than the maximum" {
    ArgumentSpecification.mustBeMaximum(3).validate(5) catch |err| {
        try std.testing.expectEqual(ArgumentSpecificationError.ArgumentsGreaterThanMaximum, err);
    };
}

test "arguments are not matching the exact" {
    ArgumentSpecification.mustBeExact(3).validate(5) catch |err| {
        try std.testing.expectEqual(ArgumentSpecificationError.ArgumentsNotMatchingExpected, err);
    };
}

test "arguments are not in end-exclusive range, given argument count is equal to the maximum argument of the range" {
    ArgumentSpecification.mustBeInEndExclusiveRange(2, 5).validate(5) catch |err| {
        try std.testing.expectEqual(ArgumentSpecificationError.ArgumentsNotInEndExclusiveRange, err);
    };
}

test "arguments are not in end-exclusive range, given argument count is less than the minimum argument of the range" {
    ArgumentSpecification.mustBeInEndExclusiveRange(2, 5).validate(1) catch |err| {
        try std.testing.expectEqual(ArgumentSpecificationError.ArgumentsNotInEndExclusiveRange, err);
    };
}

test "arguments are not in end-inclusive range, given argument count is greater than the maximum argument of the range" {
    ArgumentSpecification.mustBeInEndInclusiveRange(2, 5).validate(6) catch |err| {
        try std.testing.expectEqual(ArgumentSpecificationError.ArgumentsNotInEndInclusiveRange, err);
    };
}

test "arguments are not in end-inclusive range, given argument count is less than the minimum argument of the range" {
    ArgumentSpecification.mustBeInEndInclusiveRange(2, 5).validate(1) catch |err| {
        try std.testing.expectEqual(ArgumentSpecificationError.ArgumentsNotInEndInclusiveRange, err);
    };
}
