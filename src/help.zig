const std = @import("std");
const prettytable = @import("prettytable");

const Command = @import("commands.zig").Command;
const CommandAlias = @import("commands.zig").CommandAlias;
const CommandFnArguments = @import("commands.zig").CommandFnArguments;

const Flags = @import("flags.zig").Flags;
const Flag = @import("flags.zig").Flag;
const FlagType = @import("flags.zig").FlagType;
const ParsedFlags = @import("flags.zig").ParsedFlags;
const HelpFlagDisplayLabel = @import("flags.zig").HelpFlagDisplayLabel;

const ErrorLog = @import("log.zig").ErrorLog;

const Diagnostics = @import("diagnostics.zig").Diagnostics;

pub const CommandHelp = struct {
    command: Command,
    writer: std.io.AnyWriter,

    pub fn init(command: Command, writer: std.io.AnyWriter) CommandHelp {
        return .{
            .command = command,
            .writer = writer,
        };
    }

    pub fn printHelp(self: CommandHelp, allocator: std.mem.Allocator, flags: *Flags) !void {
        try self.writer.print("{s} - {s}\n\n", .{ self.command.name, self.command.description });
        try self.write_usage(flags, allocator);
        try self.write_aliases();
        try self.write_flags(flags, allocator);
        try self.write_subcommands(allocator);
        try self.write_global_flags(allocator);
        try self.write_deprecated_message();
    }

    fn write_usage(self: CommandHelp, flags: *Flags, allocator: std.mem.Allocator) !void {
        var usage: std.ArrayList(u8) = std.ArrayList(u8).init(allocator);
        defer usage.deinit();

        try usage.writer().print("Usage: {s}", .{self.command.name});

        switch (self.command.action) {
            .executable => {
                if (flags.flag_by_name.count() > 0) {
                    try usage.writer().writeAll(" [flags]");
                }
                try usage.writer().writeAll(" [arguments]");
            },
            .subcommands => {
                try usage.writer().writeAll(" [subcommand]");
                if (flags.flag_by_name.count() > 0) {
                    try usage.writer().writeAll(" [flags]");
                }
                try usage.writer().writeAll(" [arguments]");
            },
        }
        try self.writer.print("{s} \n\n", .{usage.items});
    }

    fn write_aliases(self: CommandHelp) !void {
        var table = prettytable.Table.init(std.testing.allocator);
        defer table.deinit();

        table.setFormat(prettytable.FORMAT_CLEAN);

        try self.command.printAliases(&table, self.writer);
        try self.writer.print("\n", .{});
    }

    fn write_flags(self: CommandHelp, flags: *Flags, allocator: std.mem.Allocator) !void {
        if (flags.flag_by_name.count() > 0) {
            var table = prettytable.Table.init(std.testing.allocator);
            defer table.deinit();

            table.setFormat(prettytable.FORMAT_CLEAN);

            try flags.print(&table, allocator, self.writer);
            try self.writer.print("\n", .{});
        }
    }

    fn write_subcommands(self: CommandHelp, allocator: std.mem.Allocator) !void {
        switch (self.command.action) {
            .subcommands => |commands| {
                var table = prettytable.Table.init(std.testing.allocator);
                defer table.deinit();

                table.setFormat(prettytable.FORMAT_CLEAN);

                try commands.print(&table, allocator, self.writer);
                try self.writer.print("\n", .{});
            },
            else => {},
        }
    }

    fn write_global_flags(self: CommandHelp, allocator: std.mem.Allocator) !void {
        var table = prettytable.Table.init(allocator);
        defer table.deinit();

        table.setFormat(prettytable.FORMAT_CLEAN);

        try self.writer.writeAll("Global options:\n");
        try table.addRow(&[_][]const u8{ HelpFlagDisplayLabel, "Show help for command" });

        try table.print(self.writer);
        try self.writer.print("\n\n", .{});
    }

    fn write_deprecated_message(self: CommandHelp) !void {
        if (self.command.deprecated_message) |msg| {
            try self.writer.print("Deprecated: {s}\n\n", .{msg});
        }
    }
};

test "print command help for a command that has no subcommands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = Command.init("stringer", "manipulate strings", runnable, ErrorLog.initNoOperation(), std.testing.allocator);
    defer command.deinit();

    command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var diagnostics: Diagnostics = .{};
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(Flag.builder("verbose", "describe verbosity", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder("priority", "describe priority", FlagType.int64).build(), &diagnostics);
    try flags.addFlag(Flag.builder("timeout", "define timeout", FlagType.int64).build(), &diagnostics);

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    var command_help = CommandHelp.init(command, writer.any());

    try command_help.printHelp(std.testing.allocator, &flags);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "stringer").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "str").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "strm").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "verbose").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "priority").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "timeout").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "-h").? > 0);
}

test "print command help for a command that has subcommands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var command = try Command.initParent("stringer", "manipulate strings", ErrorLog.initNoOperation(), std.testing.allocator);
    defer command.deinit();
    command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var sub_command = Command.init("reverse", "reverse strings", runnable, ErrorLog.initNoOperation(), std.testing.allocator);
    defer sub_command.deinit();

    try command.addSubcommand(&sub_command);

    var diagnostics: Diagnostics = .{};
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(Flag.builder("verbose", "describe verbosity", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder("priority", "describe priority", FlagType.int64).build(), &diagnostics);
    try flags.addFlag(Flag.builder("timeout", "define timeout", FlagType.int64).build(), &diagnostics);

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    var command_help = CommandHelp.init(command, writer.any());

    try command_help.printHelp(std.testing.allocator, &flags);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "stringer").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "str").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "strm").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "reverse").? > 0);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "verbose").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "priority").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "timeout").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "-h").? > 0);
}
