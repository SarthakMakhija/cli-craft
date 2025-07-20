<p align="center">
  <img width="512" height="512" alt="cli-craft logo-compressed" src="https://github.com/user-attachments/assets/ce39a176-a451-4307-b37d-44fc99019a70" />
</p>

# cli-craft

[![cli-craft CI](https://github.com/SarthakMakhija/cli-craft/actions/workflows/build.yml/badge.svg)](https://github.com/SarthakMakhija/cli-craft/actions/workflows/build.yml)

CliCraft is a a **robust framework for building command-line interface (CLI) applications in Zig**. It provides a structured and idiomatic way to define commands, subcommands, flags, and arguments, ensuring a robust and user-friendly experience.

### Adding cli-craft as a dependency

1. **Fetch the Dependency**

Add *cli-craft* to your project's `build.zig.zon` file via `zig fetch`. You can specify a particular version or commit hash, for example, using the provided example which pins to a specific commit:
```shell
zig fetch https://github.com/SarthakMakhija/cli-craft/archive/6d1030db84fda7e85a5eb792b1120e358a88f0c3.tar.gz --save
```

2. **Configure build.zig**

In your project's `build.zig`, you need to declare *cli-craft* as a dependency and then import its module into your executable, library, or test modules.

First, inside your build function load the dependency:

```zig
// Load the cli-craft dependency
const clicraft_dependency = b.dependency("cli_craft", .{});
const clicraft_module = clicraft_dependency.module("cli_craft");
```

Then, add `cli_craft_module` as an import to your respective modules (e.g., for your executable and unit tests):

```zig
// For your executable (replace 'exe_module' with your actual module variable)
exe_module.addImport("cli_craft", clicraft_module);

// Similarly for your unit tests (replace 'lib_unit_tests' with your actual test runner variable)
lib_unit_tests.root_module.addImport("cli_craft", clicraft_module);
```

After these steps, you can use

```zig 
const CliCraft = @import("cli_craft").CliCraft;
```
in your Zig source files.

### Usage

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var cliCraft = try CliCraft.init(.{ .allocator = gpa.allocator(), .error_options = .{
        .writer = std.io.getStdErr().writer().any(),
    }, .output_options = .{
        .writer = std.io.getStdOut().writer().any(),
    } });

    defer cliCraft.deinit();

    var command = try cliCraft.newParentCommand("arithmetic", "Performs arithmetic operations");
    try command.setAliases(&[_]CommandAlias{"math"});

    try registerSubCommandAdd(cliCraft, &command);
    try cliCraft.addCommand(&command);

    cliCraft.execute() catch {};
}

fn registerSubCommandAdd(cliCraft: CliCraft, command: *Command) !void {
    const runnable = struct {
        pub fn run(_: ParsedFlags, arguments: CommandFnArguments) anyerror!void {
            var sum: u8 = 0;
            for (arguments) |arg| {
                sum += try std.fmt.parseInt(u8, arg, 10);
            }
            std.debug.print("Sum = {d} \n", .{sum});
            return;
        }
    }.run;

    var subcommand = try cliCraft.newExecutableCommand("add", "Adds N arguments", runnable);
    try subcommand.setAliases(&[_]CommandAlias{"plus"});

    try command.addSubcommand(&subcommand);
}
```

### Examples

The examples are available [here](https://github.com/SarthakMakhija/cli-craft-examples).

### Zig version

This project is built with Zig version **0.14.1**.

### Features

- **Command Parsing and Execution:** Efficiently interpret and execute commands based on user input.
- **Parent and Child Commands:** Organize your CLI with parent and child commands, enabling clean, nested subcommands.
- **Command Aliases:** Support for alternative command names to enhance user convenience.
-  **Flags**:
    * Full support for defining and parsing command-line flags.
    * **Local and Persistent Flags**: Distinguish between flags scoped to a specific command and those inherited by subcommands.
    * **Early Conflict Detection**: `cli-craft` performs early detection of potential flag conflicts between parent and child commands, ensuring a well-defined CLI structure.
    * **Typed Flags**: Built-in support for `int64`, `bool`, and `string` types.
    * **Short Names for Flags**: Support for single-character aliases (e.g., `-v` for `--verbose`).
    * **Boolean Flags with and without Value**: Handle both implicit (`--verbose`) and explicit (`--verbose true`) boolean flag values.
    * **Flags with Default Values**: Assign default values to flags, which are used if the flag is not provided by the user.
- **Arguments:** Define and validate positional arguments for your commands.
- **Argument Specification:** Specify argument rules such as exact, minimum, or maximum count.
- **Boolean Flags with and without Value:** Handle both implicit (`--verbose`) and explicit (`--verbose true`) boolean flag values.
- **Help Command:** Automatically generated help command.
- **Help Flag:** Automatic `--help` or `-h` flag for each command and subcommand.
- **Robust and Tested:** Backed by extensive testing to ensure correctness and reliability..

### Current Limitations

- Does **not** support `--flag=value` syntax; only space-separated values (`--flag value`) are accepted.
- Does **not** support combined short flags (e.g., `-vpf`); each flag must be written separately (`-v -p -f`).
- **Limited type support** for flags.

### Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.

### License
This project is licensed under the MIT License - see the [LICENSE](https://github.com/SarthakMakhija/cli-craft/blob/main/LICENSE) file for details.
