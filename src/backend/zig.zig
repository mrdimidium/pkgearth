const std = @import("std");
const SemanticVersion = std.SemanticVersion;

const stdx = @import("../stdx.zig");

const Source = @This();

const ZIG_ORIGIN: []const u8 = "https://ziglang.org";

/// Describes a single file stored at `ziglang.org/download/`.
///
/// The tarball naming has changed several times. When parsing,
/// we standardize the files, but for the reverse operation
/// (getting a string from a tarball), we preserve the original path.
///
/// Does not own memory, stores only slices of the strings in the passed string.
pub const Tarball = struct {
    filename: []const u8,

    type: enum { source, bootstrap, binary },
    minisig: bool = false,
    archive: enum { zip, tarxz },
    version: SemanticVersion,
    development: bool = false,

    os: ?[]const u8 = null,
    arch: ?[]const u8 = null,

    const ParseError = error{InvalidTarball};

    pub fn getUpstreamUri(self: Tarball, url: []u8) ![]const u8 {
        var writer = std.Io.Writer.fixed(url);
        try writer.writeAll(ZIG_ORIGIN);

        if (self.development) {
            try writer.writeAll("/builds/");
        } else {
            try writer.writeAll("/download/");
            try self.version.format(&writer);
            try writer.writeByte('/');
        }
        try writer.writeAll(self.filename);
        try writer.writeAll("?source=zorian");

        return writer.buffered();
    }

    pub fn parse(zigfile: []const u8) ParseError!Tarball {
        var buffer = zigfile;
        var tarball = Tarball{
            .filename = zigfile,
            .type = undefined,
            .archive = undefined,
            .version = undefined,
        };

        // (?:|-bootstrap|-[a-zA-Z0-9_]+-[a-zA-Z0-9_]+)-(\d+\.\d+\.\d+(?:-dev\.\d+\+[0-9a-f]+)?)\.(?:tar\.xz|zip)(?:\.minisig)?
        if (stdx.cutPrefix(u8, buffer, "zig-")) |path| {
            buffer = path;
        } else {
            return ParseError.InvalidTarball;
        }

        // (?:|bootstrap|[a-zA-Z0-9_]+-[a-zA-Z0-9_]+)-(\d+\.\d+\.\d+(?:-dev\.\d+\+[0-9a-f]+)?)\.(?:tar\.xz|zip)
        if (stdx.cutSuffix(u8, buffer, ".minisig")) |path| {
            buffer = path;
            tarball.minisig = true;
        }

        // (?:|bootstrap|[a-zA-Z0-9_]+-[a-zA-Z0-9_]+)-(\d+\.\d+\.\d+(?:-dev\.\d+\+[0-9a-f]+)?)
        if (stdx.cutSuffix(u8, buffer, ".zip")) |path| {
            buffer = path;
            tarball.archive = .zip;
        } else if (stdx.cutSuffix(u8, buffer, ".tar.xz")) |path| {
            buffer = path;
            tarball.archive = .tarxz;
        } else {
            return ParseError.InvalidTarball;
        }

        if (buffer.len < 1) {
            return ParseError.InvalidTarball;
        }

        var it = std.mem.splitBackwardsScalar(u8, buffer, '-');
        const last = it.next() orelse return ParseError.InvalidTarball;

        tarball.development = std.mem.startsWith(u8, last, "dev");

        tarball.version = SemanticVersion.parse(
            if (!tarball.development) last else blk: {
                const semver = it.next() orelse return ParseError.InvalidTarball;
                const devver = last;
                break :blk stdx.overlapSlices(u8, zigfile, semver, devver);
            },
        ) catch {
            return ParseError.InvalidTarball;
        };

        if (it.next()) |payload| {
            if (std.mem.eql(u8, payload, "bootstrap")) {
                tarball.type = .bootstrap;
            } else {
                tarball.type = .binary;

                // Version 0.14.0 is the last one to use the OS-ARCH format in names; newer versions use ARCH-OS.
                const min_version = SemanticVersion{ .major = 0, .minor = 14, .patch = 0 };
                if (SemanticVersion.order(tarball.version, min_version) == .gt) {
                    tarball.os = payload;
                    tarball.arch = it.next() orelse return ParseError.InvalidTarball;
                } else {
                    tarball.arch = payload;
                    tarball.os = it.next() orelse return ParseError.InvalidTarball;
                }
            }
        } else {
            tarball.type = .source;
        }

        if (it.next() != null) {
            return ParseError.InvalidTarball;
        }

        return tarball;
    }

    test "parse" {
        const expectEqualDeep = std.testing.expectEqualDeep;

        for ([_]Tarball{
            Tarball{
                .filename = "zig-0.16.0-dev.1326+2e6f7d36b.tar.xz",
                .type = .source,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.16.0-dev.1326+2e6f7d36b"),
                .development = true,
            },
            Tarball{
                .filename = "zig-0.16.0-dev.1326+2e6f7d36b.tar.xz.minisig",
                .type = .source,
                .minisig = true,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.16.0-dev.1326+2e6f7d36b"),
                .development = true,
            },

            // 0.14.1 (new tarball name format, some new targets)
            Tarball{
                .filename = "zig-0.14.1.tar.xz",
                .type = .source,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.14.1"),
            },
            Tarball{
                .filename = "zig-0.14.1.tar.xz.minisig",
                .minisig = true,
                .type = .source,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.14.1"),
            },
            Tarball{
                .filename = "zig-x86_64-windows-0.14.1.zip",
                .type = .binary,
                .archive = .zip,
                .version = try SemanticVersion.parse("0.14.1"),
                .os = "windows",
                .arch = "x86_64",
            },
            Tarball{
                .filename = "zig-riscv64-linux-0.14.1.tar.xz",
                .type = .binary,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.14.1"),
                .os = "linux",
                .arch = "riscv64",
            },
            Tarball{
                .filename = "zig-aarch64-macos-0.14.1.tar.xz",
                .type = .binary,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.14.1"),
                .os = "macos",
                .arch = "aarch64",
            },

            // 0.10.1 (last stage1 release)
            Tarball{
                .filename = "zig-0.10.1.tar.xz",
                .type = .source,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.10.1"),
            },
            Tarball{
                .filename = "zig-bootstrap-0.10.1.tar.xz",
                .type = .bootstrap,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.10.1"),
            },
            Tarball{
                .filename = "zig-linux-i386-0.10.1.tar.xz",
                .type = .binary,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.10.1"),
                .os = "linux",
                .arch = "i386",
            },

            // 0.7.1 (oldest supported patch release)
            Tarball{
                .filename = "zig-0.7.1.tar.xz",
                .type = .source,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.7.1"),
            },
            Tarball{
                .filename = "zig-linux-x86_64-0.7.1.tar.xz",
                .type = .binary,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.7.1"),
                .os = "linux",
                .arch = "x86_64",
            },

            // 0.6.0 (oldest supported version)
            Tarball{
                .filename = "zig-0.6.0.tar.xz",
                .type = .source,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.6.0"),
            },
            Tarball{
                .filename = "zig-linux-x86_64-0.6.0.tar.xz",
                .type = .binary,
                .archive = .tarxz,
                .version = try SemanticVersion.parse("0.6.0"),
                .os = "linux",
                .arch = "x86_64",
            },
        }) |tarball| {
            try expectEqualDeep(tarball, try Tarball.parse(tarball.filename));
        }
    }

    test "parse is garbage-tolerant" {
        const Context = struct {
            fn testOne(_: @This(), input: []const u8) anyerror!void {
                try std.testing.expectError(
                    ParseError.InvalidTarball,
                    Tarball.parse(input),
                );
            }
        };
        try std.testing.fuzz(Context{}, Context.testOne, .{});
    }
};
