//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

// Re-exporting public API structs
pub const Command = @import("command.zig");
pub const Commands = @import("commands.zig");
pub const ArgumentSpecification = @import("argument-specification.zig");

test {
    // Reference all tests from modules
    std.testing.refAllDecls(@This());
}
