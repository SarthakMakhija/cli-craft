const std = @import("std");

pub const ErrorLog = struct {
    writer: std.fs.File.Writer,

    pub fn init(writer: std.fs.File.Writer) ErrorLog {
        return .{
            .writer = writer,
        };
    }

    pub fn log(self: ErrorLog, comptime message: []const u8, args: anytype) void {
        self.writer.print(message, args) catch {};
    }
};
