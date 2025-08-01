- [X] Add support for defining a command
- [X] Add support for adding a command
- [X] Add support for getting a command based on name
- [X] Add support for getting a command based on name
- [X] Add support for validating arguments of a command
- [X] Add support for parsing commands without flags
- [X] Add support for executing a leaf command
- [X] Add support for identifying parent command
- [X] Multi-OS pipeline
    - [X] Ubuntu-latest (x86_64)
    - [X] Windows-latest (x86_64)
- [X] Hierarchical deinit in Commands
- [X] Add support for logging/printing
- [X] Add errors on console 
    - [X] Pass a single ErrorLog
    - [ ] Revisit diagnostics across all the methods
    - [X] Add argument specification errors in diagnostics
- [X] Support Help for a command
    - [X] Add support for printing a single command
    - [X] Integrate printing
    - [X] Print command help on execution errors
- [X] Support Help for all commands
    - [X] Add support for printing all commands
    - [X] Integrate printing
- [X] Add support for local flags
- [X] Add support for executing commands with local flags
- [X] Add support for passing flags with default value
- [X] Add support for persistent flags
- [X] Add support for executing commands with persistent flags
- [X] Revalidate the design of FlagType and FlagValue
- [X] Refactor CommandLineParser to build a state machine
- [X] Add tests to see the behavior when the same flag is passed from parent command and child command during execution
- [X] Remove logging errors in execute / cli-craft.execute ..
- [X] Ensure that the same flag can not be local and persistent
- [X] Revalidate the arguments of run function in a command
- [X] Revisit export of public APIs + errors
- [X] Copy the command name, description, usage, alias + flag name, description, flag value
- [X] Convert aliases to list
- [X] An entrypoint of the cli-craft library
- [ ] An example project
- [X] Correct all tests which return error, the unit tests need to ensure that the tests fail if error is not returned
- [ ] README
- [X] Code documentation
- [ ] Release the library