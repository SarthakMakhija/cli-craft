### cli-craft
[![cli-craft CI](https://github.com/SarthakMakhija/cli-craft/actions/workflows/build.yml/badge.svg)](https://github.com/SarthakMakhija/cli-craft/actions/workflows/build.yml)

CliCraft is a a **robust framework for building command-line interface (CLI) applications in Zig**. It provides a structured and idiomatic way to define commands, subcommands, flags, and arguments, ensuring a robust and user-friendly experience.

### Getting Started

Coming soon

### Usage

Coming soon

### Examples

Coming soon

### Features

- **Command Parsing and Execution:** Seamlessly parse and execute commands based on user input.
- **Parent and Child Commands:** Organize your CLI into a hierarchical structure with nested subcommands.
- **Command Aliases:** Define alternative names for your commands for user convenience.
- **Flags:** Comprehensive support for defining and parsing command-line flags.
- **Local and Persistent Flags:** Differentiate between flags applicable only to a specific command (local) and those inherited by its subcommands (persistent).
- **Typed Flags:** Support for `int64`, `boolean`, and `string` flag types.
- **Short Names for Flags:** Provide single-character short names for flags (e.g., ``-v`` for ``--verbose``).
- **Arguments:** Define and validate positional arguments for your commands.
- **Argument Specification:** Specify argument requirements (e.g., exact count, minimum, maximum).
- **Boolean Flags with and without Value:** Handle boolean flags that can be simply present (``--verbose``) or explicitly assigned a value (``--verbose true``).
- **Flags with Default Values:** Assign default values to flags, which are used if the flag is not provided by the user.
- **Help Command:** Automatically generated and customizable help command.
- **Help Flag:** Automatic ``--help`` or ``-h`` flag for each command and subcommand.
- **Robustness:** Exhaustive tests ensure the reliability and correctness of the code.

### Current Limitations

- Does not support ``--flag=value`` syntax for flags. Only ``--flag value`` is supported.
- Does not support combined boolean flags (e.g., ``-vpf`` for ``-v -p -f``). Each short flag must be specified individually (e.g., ``-v -p -f``)

### Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.

### License
This project is licensed under the MIT License - see the [LICENSE](https://github.com/SarthakMakhija/cli-craft/blob/main/LICENSE) file for details.
