const std = @import("std");
const prettytable = @import("prettytable");

pub const ErrorLog = struct {
    writer: ?std.io.AnyWriter,

    pub fn init(writer: std.io.AnyWriter) ErrorLog {
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

pub const OutputStream = struct {
    out_writer: ?std.io.AnyWriter,
    err_writer: ?std.io.AnyWriter,

    pub fn init(out_writer: std.io.AnyWriter, err_writer: std.io.AnyWriter) OutputStream {
        return .{
            .out_writer = out_writer,
            .err_writer = err_writer,
        };
    }

    pub fn initStdErrWriter(out_writer: std.io.AnyWriter) OutputStream {
        return .{
            .out_writer = out_writer,
            .err_writer = std.io.getStdErr().writer().any(),
        };
    }

    pub fn initStdOutWriter(err_writer: std.io.AnyWriter) OutputStream {
        return .{
            .out_writer = std.io.getStdOut().writer().any(),
            .err_writer = err_writer,
        };
    }

    pub fn initNoOperationOutputStream() OutputStream {
        return .{
            .out_writer = null,
            .err_writer = null,
        };
    }

    pub fn print(self: OutputStream, comptime message: []const u8, arguments: anytype) !void {
        if (self.out_writer) |writer| {
            try writer.print(message, arguments);
        }
    }

    pub fn printAll(self: OutputStream, bytes: []const u8) !void {
        if (self.out_writer) |writer| {
            try writer.writeAll(bytes);
        }
    }

    pub fn printTable(self: OutputStream, table: *prettytable.Table) !void {
        if (self.out_writer) |writer| {
            try table.print(writer);
        }
    }

    pub fn printError(self: OutputStream, comptime message: []const u8, arguments: anytype) !void {
        if (self.err_writer) |writer| {
            try writer.print(message, arguments);
        }
    }
};
