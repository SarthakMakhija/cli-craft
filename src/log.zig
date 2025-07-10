const std = @import("std");

pub const ErrorLog = struct {
    writer: ?std.fs.File.Writer,

    pub fn init(writer: std.fs.File.Writer) ErrorLog {
        return .{ .writer = writer };
    }

    pub fn initNoOperation() ErrorLog {
        return .{ .writer = null };
    }

    pub fn log(self: ErrorLog, comptime message: []const u8, arguments: anytype) void {
        if (self.writer) |writer| {
            writer.print(message, arguments) catch {};
        }
    }
};
