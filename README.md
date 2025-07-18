<p align="center">
  <img width="512" height="512" alt="CLI-craft logo" src="https://github.com/user-attachments/assets/92851868-5ae6-434d-afe6-8e8b731189f4" />
</p>

# cli-craft

[![cli-craft CI](https://github.com/SarthakMakhija/cli-craft/actions/workflows/build.yml/badge.svg)](https://github.com/SarthakMakhija/cli-craft/actions/workflows/build.yml)

CliCraft is a a **robust framework for building command-line interface (CLI) applications in Zig**. It provides a structured and idiomatic way to define commands, subcommands, flags, and arguments, ensuring a robust and user-friendly experience.

### Getting Started

Coming soon

### Usage

Coming soon

### Examples

Coming soon

### Features

- **Command Parsing and Execution:** Efficiently interpret and execute commands based on user input.
- **Parent and Child Commands:** Organize your CLI with parent and child commands, enabling clean, nested subcommands.
- **Command Aliases:** Support for alternative command names to enhance user convenience.
- **Flags:** Full support for defining and parsing command-line flags.
- **Local and Persistent Flags:** Distinguish between flags scoped to a specific command and those inherited by subcommands.
- **Typed Flags:** Built-in support for `int64`, `bool`, and `string` types.
- **Short Names for Flags:** Support for single-character aliases (e.g., `-v` for `--verbose`).
- **Arguments:** Define and validate positional arguments for your commands.
- **Argument Specification:** Specify argument rules such as exact, minimum, or maximum count.
- **Boolean Flags with and without Value:** Handle both implicit (`--verbose`) and explicit (`--verbose true`) boolean flag values.
- **Flags with Default Values:** Assign default values to flags, which are used if the flag is not provided by the user.
- **Help Command:** Automatically generated help command.
- **Help Flag:** Automatic `--help` or `-h` flag for each command and subcommand.
- **Robust and Tested:** Backed by extensive testing to ensure correctness and reliability..

### Current Limitations

- Does **not** support `--flag=value` syntax; only space-separated values (`--flag value`) are accepted.
- Does **not** support combined short flags (e.g., `-vpf`); each flag must be written separately (`-v -p -f`).

### Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.

### License
This project is licensed under the MIT License - see the [LICENSE](https://github.com/SarthakMakhija/cli-craft/blob/main/LICENSE) file for details.
