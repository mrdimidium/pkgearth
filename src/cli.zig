//! Parses and validates command line flags

const std = @import("std");
const assert = std.debug.assert;

const globals = @import("config");

const stdx = @import("stdx.zig");

comptime {
    // Make sure the version is a valid semver
    _ = std.SemanticVersion.parse(globals.version) catch unreachable;
}

const Self = @This();

const help =
    \\Usage:
    \\  zorian [OPTION]
    \\
    \\Options:
    \\  -h, --help
    \\        Print this help message and exit.
    \\  -V, --version
    \\        Print version and exit.
    \\  --config=<file>
    \\        Path to the configuration file in zon format
    \\
;

config: []const u8 = "/etc/zorian.zon",

pub fn parse(args: *std.process.ArgIterator) Self {
    assert(args.skip()); // Discard executable name.

    var self = Self{};
    while (true) {
        const arg = args.next() orelse break;

        if (std.mem.eql(u8, "-V", arg) or
            std.mem.eql(u8, "--version", arg))
        {
            std.debug.print("{s}", .{globals.version});
            std.process.exit(0);
        }

        if (std.mem.eql(u8, "-h", arg) or
            std.mem.eql(u8, "--help", arg))
        {
            std.debug.print("{s}", .{help});
            std.process.exit(0);
        }

        if (!std.mem.startsWith(u8, arg, "--")) {
            stdx.fatal("invalid cli argument: {s}", .{arg});
        }

        const separator_pos = std.mem.indexOf(u8, arg, "=") orelse {
            stdx.fatal("cli argument must have a value: {s}", .{arg});
        };

        const name = arg[2..separator_pos];
        const value = arg[separator_pos + 1 .. arg.len];

        if (name.len < 1 or value.len < 1) {
            stdx.fatal("invalid argument: {s}", .{arg});
        }

        if (std.mem.eql(u8, "config", name)) {
            self.config = value;
        } else {
            stdx.fatal("unknown flag: {s}", .{name});
        }
    }
    return self;
}
