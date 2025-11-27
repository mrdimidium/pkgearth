const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_request_size = 16 * 1024; // 16KB
pub const max_response_size = 16 * 1024; // 16KB
pub const max_pending_connections = 128;

pub const max_configfile_size = 4096; // 4KB

const Self = @This();

server: struct {
    port: u16,
    host: []const u8,
},

storage: struct {
    dirname: []const u8,
},

pub fn parse(arena: Allocator, filename: []const u8) !Self {
    var buffer = std.mem.zeroes([max_configfile_size]u8);
    const contents = try std.fs.cwd().readFile(filename, &buffer);

    var diagnostics: std.zon.parse.Diagnostics = .{};
    defer diagnostics.deinit(arena);

    const source: [:0]u8 = try arena.dupeZ(u8, contents);
    return std.zon.parse.fromSlice(Self, arena, source, &diagnostics, .{}) catch |err|
        switch (err) {
            error.ParseZon => {
                std.debug.print("Parse diagnostics:\n{f}\n", .{diagnostics});
                std.process.exit(1);
            },
            else => return err,
        };
}
