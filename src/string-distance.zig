//! https://en.wikipedia.org/wiki/Levenshtein_distance

const std = @import("std");

pub const StringDistance = struct {
    pub fn levenshtein(allocator: std.mem.Allocator, str: []const u8, other: []const u8) !u16 {
        const str_length = str.len;
        const other_len = other.len;
        const table = try allocator.alloc(u8, str_length * other_len);
        defer allocator.free(table);

        table[0] = 0;
        for (0..str_length) |str_index| {
            for (0..other_len) |other_index| {
                table[idx(str_index, other_index, other_len)] = @min(
                    (if (str_index == 0)
                        @as(u8, @truncate(other_index))
                    else
                        table[idx(str_index - 1, other_index, other_len)]) + 1,
                    (if (other_index == 0)
                        @as(u8, @truncate(str_index))
                    else
                        table[idx(str_index, other_index - 1, other_len)]) + 1,
                    (if (str_index == 0)
                        @as(u8, @truncate(other_index))
                    else if (other_index == 0)
                        @as(u8, @truncate(str_index))
                    else
                        table[idx(str_index - 1, other_index - 1, other_len)]) +
                        @intFromBool(str[str_index] != other[other_index]),
                );
            }
        }
        return table[table.len - 1];
    }

    inline fn idx(index: usize, other_index: usize, cols: usize) usize {
        return index * cols + other_index;
    }
};

test "distance between two strings (1)" {
    try std.testing.expectEqual(1, StringDistance.levenshtein(std.testing.allocator, "hello", "hllo"));
}

test "distance between two strings (2)" {
    try std.testing.expectEqual(0, StringDistance.levenshtein(std.testing.allocator, "zig", "zig"));
}
