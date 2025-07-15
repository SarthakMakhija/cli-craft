const std = @import("std");

// Re-exporting public API structs begin
pub const Command = @import("commands.zig").Command;
pub const CommandFn = @import("commands.zig").CommandFn;
pub const CommandFnArguments = @import("commands.zig").CommandFnArguments;
pub const CommandAlias = @import("commands.zig").CommandAlias;
pub const CommandAliases = @import("commands.zig").CommandAliases;

pub const ArgumentSpecification = @import("argument-specification.zig");

pub const Flags = @import("flags.zig").Flags;
pub const Flag = @import("flags.zig").Flag;
pub const FlagType = @import("flags.zig").FlagType;
pub const FlagValue = @import("flags.zig").FlagValue;
pub const FlagErrors = @import("flags.zig").FlagErrors;
pub const Diagnostics = @import("diagnostics.zig").Diagnostics;

pub const ParsedFlags = @import("flags.zig").ParsedFlags;
pub const ParsedFlag = @import("flags.zig").ParsedFlag;
pub const CommandHelp = @import("help.zig").CommandHelp;

// Re-exporting public API structs end

const Commands = @import("commands.zig").Commands;
const Arguments = @import("arguments.zig").Arguments;

const OutputStream = @import("stream.zig").OutputStream;

pub const GlobalOptions = struct {
    application_description: ?[]const u8 = null,
    allocator: std.mem.Allocator,
    error_options: struct {
        writer: std.io.AnyWriter,
    },
    output_options: struct {
        writer: std.io.AnyWriter,
    },
};

pub const CliCraft = struct {
    options: GlobalOptions,
    commands: Commands,
    output_stream: OutputStream,

    pub fn init(options: GlobalOptions) !CliCraft {
        const output_stream = OutputStream.init(
            options.output_options.writer,
            options.error_options.writer,
        );

        var commands = Commands.init(options.allocator, output_stream);
        try commands.addHelp();

        return .{
            .options = options,
            .commands = commands,
            .output_stream = output_stream,
        };
    }

    pub fn newExecutableCommand(
        self: CliCraft,
        name: []const u8,
        description: []const u8,
        executable: CommandFn,
    ) !Command {
        return try Command.init(
            name,
            description,
            executable,
            self.output_stream,
            self.options.allocator,
        );
    }

    pub fn newParentCommand(self: CliCraft, name: []const u8, description: []const u8) !Command {
        return try Command.initParent(
            name,
            description,
            self.output_stream,
            self.options.allocator,
        );
    }

    pub fn addExecutableCommand(
        self: *CliCraft,
        name: []const u8,
        description: []const u8,
        executable: CommandFn,
    ) !void {
        try self.addCommand(
            try self.newExecutableCommand(name, description, executable),
        );
    }

    pub fn addParentCommand(self: *CliCraft, name: []const u8, description: []const u8) !void {
        try self.addCommand(
            self.newParentCommand(name, description),
        );
    }

    pub fn addCommand(self: *CliCraft, command: Command) !void {
        var diagnostics: Diagnostics = .{};

        self.commands.add_disallow_child(command, &diagnostics) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    pub fn execute(self: *CliCraft) !void {
        var diagnostics: Diagnostics = .{};

        self.commands.execute(
            self.options.application_description,
            Arguments.init(),
            &diagnostics,
        ) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    pub fn executeWithArguments(self: *CliCraft, arguments: []const []const u8) !void {
        var command_line_arguments = try Arguments.initWithArgs(arguments);
        var diagnostics: Diagnostics = .{};

        self.commands.execute(
            self.options.application_description,
            &command_line_arguments,
            &diagnostics,
        ) catch |err| {
            diagnostics.log_using(self.output_stream);
            return err;
        };
    }

    pub fn deinit(self: *CliCraft) void {
        self.commands.deinit();
    }
};

test {
    // Reference all tests from modules
    std.testing.refAllDecls(@This());
}

var add_command_result: u8 = undefined;
var get_command_result: []const u8 = undefined;

test "execute an executable command with arguments" {
    var cliCraft = try CliCraft.init(.{ .allocator = std.testing.allocator, .error_options = .{
        .writer = std.io.getStdErr().writer().any(),
    }, .output_options = .{
        .writer = std.io.getStdOut().writer().any(),
    } });

    defer cliCraft.deinit();

    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            add_command_result = augend + addend;
            return;
        }
    }.run;

    try cliCraft.addExecutableCommand("add", "adds numbers", runnable);
    try cliCraft.executeWithArguments(&[_][]const u8{ "add", "21", "51" });

    try std.testing.expectEqual(72, add_command_result);
}

test "execute an executable command with arguments and flags" {
    var cliCraft = try CliCraft.init(.{ .allocator = std.testing.allocator, .error_options = .{
        .writer = std.io.getStdErr().writer().any(),
    }, .output_options = .{
        .writer = std.io.getStdOut().writer().any(),
    } });

    defer cliCraft.deinit();

    const runnable = struct {
        pub fn run(parsed_flags: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            const augend = try std.fmt.parseInt(u8, arguments[0], 10);
            const addend = try std.fmt.parseInt(u8, arguments[1], 10);

            try std.testing.expect(try parsed_flags.getBoolean("verbose"));
            try std.testing.expect(try parsed_flags.getBoolean("priority"));
            try std.testing.expectEqual(23, try parsed_flags.getInt64("timeout"));

            add_command_result = augend + addend;
            return;
        }
    }.run;

    var command = try cliCraft.newExecutableCommand(
        "add",
        "adds numbers",
        runnable,
    );
    try command.addFlag(
        Flag.builder(
            "verbose",
            "Enable verbose output",
            FlagType.boolean,
        ).build(),
    );
    try command.addFlag(Flag.builder(
        "priority",
        "Enable priority",
        FlagType.boolean,
    ).build());
    try command.addFlag(Flag.builder_with_default_value(
        "timeout",
        "Define timeout",
        FlagValue.type_int64(25),
    ).withShortName('t').build());

    try cliCraft.addCommand(command);
    try cliCraft.executeWithArguments(
        &[_][]const u8{ "add", "-t", "23", "2", "5", "--verbose", "--priority" },
    );

    try std.testing.expectEqual(7, add_command_result);
}

test "execute a command with subcommand" {
    var cliCraft = try CliCraft.init(.{ .allocator = std.testing.allocator, .error_options = .{
        .writer = std.io.getStdErr().writer().any(),
    }, .output_options = .{
        .writer = std.io.getStdOut().writer().any(),
    } });

    defer cliCraft.deinit();

    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            get_command_result = arguments[0];
        }
    }.run;

    var get_command = try cliCraft.newExecutableCommand(
        "get",
        "get objects",
        runnable,
    );
    var kubectl_command = try cliCraft.newParentCommand(
        "kubectl",
        "kubernetes entry",
    );
    try kubectl_command.addSubcommand(&get_command);

    try cliCraft.addCommand(kubectl_command);
    try cliCraft.executeWithArguments(&[_][]const u8{ "kubectl", "get", "pods" });

    try std.testing.expectEqual(7, add_command_result);
}
