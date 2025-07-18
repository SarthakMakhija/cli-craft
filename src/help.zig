const std = @import("std");
const prettytable = @import("prettytable");

const Command = @import("commands.zig").Command;
const CommandAlias = @import("commands.zig").CommandAlias;
const CommandFnArguments = @import("commands.zig").CommandFnArguments;
const ArgumentSpecification = @import("argument-specification.zig").ArgumentSpecification;

const Commands = @import("commands.zig").Commands;

const Flags = @import("flags.zig").Flags;
const Flag = @import("flags.zig").Flag;
const FlagType = @import("flags.zig").FlagType;
const ParsedFlags = @import("flags.zig").ParsedFlags;
const HelpFlagDisplayLabel = @import("flags.zig").HelpFlagDisplayLabel;

const OutputStream = @import("stream.zig").OutputStream;
const Diagnostics = @import("diagnostics.zig").Diagnostics;

pub const CommandHelp = struct {
    command: Command,
    output_stream: OutputStream,

    pub fn init(command: Command, output_stream: OutputStream) CommandHelp {
        return .{
            .command = command,
            .output_stream = output_stream,
        };
    }

    pub fn printHelp(self: CommandHelp, allocator: std.mem.Allocator, flags: *Flags) !void {
        try self.output_stream.print("{s} - {s}\n\n", .{ self.command.name, self.command.description });
        try self.write_usage(flags, allocator);
        try self.write_aliases();
        try self.write_flags(flags, allocator);
        try self.write_argument_specification(allocator);
        try self.write_subcommands(allocator);
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
        try self.output_stream.print("{s} \n", .{usage.items});
    }

    fn write_aliases(self: CommandHelp) !void {
        var table = prettytable.Table.init(std.testing.allocator);
        defer table.deinit();

        table.setFormat(prettytable.FORMAT_CLEAN);

        try self.command.printAliases(&table);
        try self.output_stream.print("\n", .{});
    }

    fn write_flags(self: CommandHelp, flags: *Flags, allocator: std.mem.Allocator) !void {
        if (flags.flag_by_name.count() > 0) {
            var table = prettytable.Table.init(std.testing.allocator);
            defer table.deinit();

            table.setFormat(prettytable.FORMAT_CLEAN);

            try flags.print(&table, self.output_stream, allocator);
            try self.output_stream.print("\n", .{});
        }
    }

    fn write_argument_specification(self: CommandHelp, allocator: std.mem.Allocator) !void {
        if (self.command.argument_specification) |argument_specification| {
            try argument_specification.print(self.output_stream, allocator);
            try self.output_stream.print("\n", .{});
        }
    }

    fn write_subcommands(self: CommandHelp, allocator: std.mem.Allocator) !void {
        switch (self.command.action) {
            .subcommands => |commands| {
                var table = prettytable.Table.init(std.testing.allocator);
                defer table.deinit();

                table.setFormat(prettytable.FORMAT_CLEAN);

                try commands.print(&table, allocator);
                try self.output_stream.print("\n", .{});
            },
            else => {},
        }
    }
};

pub const CommandsHelp = struct {
    commands: Commands,
    output_stream: OutputStream,
    app_description: ?[]const u8,

    pub fn init(commands: Commands, app_description: ?[]const u8, output_stream: OutputStream) CommandsHelp {
        return .{
            .commands = commands,
            .output_stream = output_stream,
            .app_description = app_description,
        };
    }

    pub fn printHelp(self: CommandsHelp, allocator: std.mem.Allocator) !void {
        if (self.app_description) |app_description| {
            try self.output_stream.print("{s}\n", .{app_description});
        }
        try self.write_usage(allocator);
        try self.write_allcommands(allocator);
        try self.write_global_flags(allocator);
    }

    fn write_usage(self: CommandsHelp, allocator: std.mem.Allocator) !void {
        var usage: std.ArrayList(u8) = std.ArrayList(u8).init(allocator);
        defer usage.deinit();

        try usage.writer().print("Usage: [app-name] [command] [flags] [arguments]", .{});
        try self.output_stream.print("\n", .{});
    }

    fn write_allcommands(self: CommandsHelp, allocator: std.mem.Allocator) !void {
        var table = prettytable.Table.init(std.testing.allocator);
        defer table.deinit();

        table.setFormat(prettytable.FORMAT_CLEAN);

        try self.commands.print(&table, allocator);
        try self.output_stream.print("\n", .{});
    }

    fn write_global_flags(self: CommandsHelp, allocator: std.mem.Allocator) !void {
        var table = prettytable.Table.init(allocator);
        defer table.deinit();

        table.setFormat(prettytable.FORMAT_CLEAN);

        try self.output_stream.printAll("Global flags:\n");
        try table.addRow(&[_][]const u8{ HelpFlagDisplayLabel, "Show help for command" });

        try self.output_stream.printTable(&table);
        try self.output_stream.print("\n", .{});
    }
};

test "print command help for a command that has no subcommands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var command = try Command.init("stringer", "manipulate strings", runnable, output_stream, std.testing.allocator);
    defer command.deinit();

    try command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var diagnostics: Diagnostics = .{};
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(Flag.builder("verbose", "describe verbosity", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder("priority", "describe priority", FlagType.int64).build(), &diagnostics);
    try flags.addFlag(Flag.builder("timeout", "define timeout", FlagType.int64).build(), &diagnostics);
    try flags.addHelp();

    var command_help = CommandHelp.init(command, output_stream);

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

test "print command help for a command with argument specification that has no subcommands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var command = try Command.init("stringer", "manipulate strings", runnable, output_stream, std.testing.allocator);
    try command.setArgumentSpecification(ArgumentSpecification.mustBeExact(1));
    defer command.deinit();

    try command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var diagnostics: Diagnostics = .{};
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(Flag.builder("verbose", "describe verbosity", FlagType.boolean).build(), &diagnostics);
    try flags.addHelp();

    var command_help = CommandHelp.init(command, output_stream);
    try command_help.printHelp(std.testing.allocator, &flags);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "stringer").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "str").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "strm").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "verbose").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "-h").? > 0);
}

test "print command help for a command that has subcommands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var command = try Command.initParent("stringer", "manipulate strings", output_stream, std.testing.allocator);
    defer command.deinit();
    try command.addAliases(&[_]CommandAlias{ "str", "strm" });

    var sub_command = try Command.init("reverse", "reverse strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);

    try command.addSubcommand(&sub_command);

    var diagnostics: Diagnostics = .{};
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();

    try flags.addFlag(Flag.builder("verbose", "describe verbosity", FlagType.boolean).build(), &diagnostics);
    try flags.addFlag(Flag.builder("priority", "describe priority", FlagType.int64).build(), &diagnostics);
    try flags.addFlag(Flag.builder("timeout", "define timeout", FlagType.int64).build(), &diagnostics);
    try flags.addHelp();

    var command_help = CommandHelp.init(command, output_stream);

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

test "print all commands" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var stringer_command = try Command.initParent("stringer", "manipulate strings", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try stringer_command.addAliases(&[_][]const u8{ "str", "strm" });

    var reverse_command = try Command.init("reverse", "reverse strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try reverse_command.addAliases(&[_][]const u8{"rev"});

    var diagnostics: Diagnostics = .{};
    var commands = Commands.init(std.testing.allocator, output_stream);
    defer commands.deinit();

    try commands.add_disallow_child(&stringer_command, &diagnostics);
    try commands.add_disallow_child(&reverse_command, &diagnostics);

    var commands_help = CommandsHelp.init(commands, null, output_stream);

    try commands_help.printHelp(std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "stringer").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "str").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "strm").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "reverse").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "rev").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "-h").? > 0);
}

test "print all commands with application description" {
    const runnable = struct {
        pub fn run(_: ParsedFlags, _: CommandFnArguments) anyerror!void {
            return;
        }
    }.run;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    const output_stream = OutputStream.initStdErrWriter(writer.any());

    var stringer_command = try Command.initParent("stringer", "manipulate strings", OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try stringer_command.addAliases(&[_][]const u8{ "str", "strm" });

    var reverse_command = try Command.init("reverse", "reverse strings", runnable, OutputStream.initNoOperationOutputStream(), std.testing.allocator);
    try reverse_command.addAliases(&[_][]const u8{"rev"});

    var diagnostics: Diagnostics = .{};
    var commands = Commands.init(std.testing.allocator, output_stream);
    defer commands.deinit();

    try commands.add_disallow_child(&stringer_command, &diagnostics);
    try commands.add_disallow_child(&reverse_command, &diagnostics);

    var commands_help = CommandsHelp.init(commands, "application for manipulating strings", output_stream);

    try commands_help.printHelp(std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "application for manipulating strings").? >= 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "stringer").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "str").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "strm").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "reverse").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "rev").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "--help").? > 0);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "-h").? > 0);
}
