const std = @import("std");
const prettytable = @import("prettytable");

/// A utility struct for managing and directing standard output and error output.
///
/// This provides a unified interface for printing messages and tables,
/// abstracting away the underlying `std.io.AnyWriter` instances. It supports
/// optional writers, allowing for "no-operation" streams for testing or
/// silent execution.
pub const OutputStream = struct {
    /// The writer for standard output. Can be `null` if no output is desired.
    out_writer: ?std.io.AnyWriter,
    /// The writer for error output. Can be `null` if no error output is desired.
    err_writer: ?std.io.AnyWriter,

    /// Initializes an `OutputStream` with distinct writers for standard output and error output.
    ///
    /// Parameters:
    ///   out_writer: The `std.io.AnyWriter` to use for standard output.
    ///   err_writer: The `std.io.AnyWriter` to use for error output.
    pub fn init(out_writer: std.io.AnyWriter, err_writer: std.io.AnyWriter) OutputStream {
        return .{
            .out_writer = out_writer,
            .err_writer = err_writer,
        };
    }

    /// Initializes an `OutputStream` where standard error output is directed to `std.io.getStdErr()`.
    ///
    /// Parameters:
    ///   out_writer: The `std.io.AnyWriter` to use for standard output.
    pub fn initStdErrWriter(out_writer: std.io.AnyWriter) OutputStream {
        return .{
            .out_writer = out_writer,
            .err_writer = std.io.getStdErr().writer().any(),
        };
    }

    /// Initializes an `OutputStream` where standard output is directed to `std.io.getStdOut()`.
    ///
    /// Parameters:
    ///   err_writer: The `std.io.AnyWriter` to use for error output.
    pub fn initStdOutWriter(err_writer: std.io.AnyWriter) OutputStream {
        return .{
            .out_writer = std.io.getStdOut().writer().any(),
            .err_writer = err_writer,
        };
    }

    /// Initializes an `OutputStream` that performs no operations (i.e., discards all output).
    ///
    /// This is useful for testing scenarios where you want to suppress all output.
    pub fn initNoOperationOutputStream() OutputStream {
        return .{
            .out_writer = null,
            .err_writer = null,
        };
    }

    /// Prints a formatted message to the standard output stream.
    ///
    /// The message is formatted using `std.fmt.format`. If `out_writer` is null,
    /// no operation occurs.
    ///
    /// Parameters:
    ///   message: The format string.
    ///   arguments: The arguments to format into the message.
    pub fn print(self: OutputStream, comptime message: []const u8, arguments: anytype) !void {
        if (self.out_writer) |writer| {
            try writer.print(message, arguments);
        }
    }

    /// Writes a raw byte slice to the standard output stream.
    ///
    /// If `out_writer` is null, no operation occurs.
    ///
    /// Parameters:
    ///   bytes: The byte slice to write.
    pub fn printAll(self: OutputStream, bytes: []const u8) !void {
        if (self.out_writer) |writer| {
            try writer.writeAll(bytes);
        }
    }

    /// Prints a `prettytable.Table` to the standard output stream.
    ///
    /// If `out_writer` is null, no operation occurs.
    ///
    /// Parameters:
    ///   table: A pointer to the `prettytable.Table` to print.
    pub fn printTable(self: OutputStream, table: *prettytable.Table) !void {
        if (self.out_writer) |writer| {
            try table.print(writer);
        }
    }

    /// Prints a formatted message to the error output stream.
    ///
    /// The message is formatted using `std.fmt.format`. If `err_writer` is null, no operation occurs.
    ///
    /// Parameters:
    ///   message: The format string.
    ///   arguments: The arguments to format into the message.
    pub fn printError(self: OutputStream, comptime message: []const u8, arguments: anytype) !void {
        if (self.err_writer) |writer| {
            try writer.print(message, arguments);
        }
    }
};

test "print on the given writer" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();

    const output_stream = OutputStream.initStdErrWriter(writer.any());
    try output_stream.print("{s}", .{"test message"});

    try std.testing.expectEqualStrings("test message", buffer.items);
}

test "print on the given error writer" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();

    const output_stream = OutputStream.initStdOutWriter(writer.any());
    try output_stream.printError("{s}", .{"test message"});

    try std.testing.expectEqualStrings("test message", buffer.items);
}

test "print all the given writer" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();

    const output_stream = OutputStream.initStdErrWriter(writer.any());
    try output_stream.printAll("test message");

    try std.testing.expectEqualStrings("test message", buffer.items);
}

test "print table" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();

    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var table = prettytable.Table.init(std.testing.allocator);
    defer table.deinit();

    table.setFormat(prettytable.FORMAT_CLEAN);

    try table.addRow(&[_][]const u8{ "help", "Show help for command" });
    try output_stream.printTable(&table);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "help").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Show help for command").? >= 0);
}
