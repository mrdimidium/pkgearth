const std = @import("std");
const posix = std.posix;
const assert = std.debug.assert;

const stdx = @import("./stdx.zig");
const http = @import("./http.zig");
const config = @import("./config.zig");
const backendZig = @import("./backend_zig.zig");

const openssl = @cImport({
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("openssl/bio.h");
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

const response_ok =
    "HTTP/1.1 200 OK\r\n" ++
    "Content-Type: application/octet-stream\r\n" ++
    "Content-Length: {d}\r\n" ++
    "Connection: close\r\n" ++
    "\r\n";

const response_not_found =
    "HTTP/1.1 404 Not Found\r\n" ++
    "Content-Length: 0\r\n" ++
    "Connection: close\r\n";

const response_bad_request =
    "HTTP/1.1 400 Bad Request\r\n" ++
    "Content-Length: 0\r\n" ++
    "Connection: close\r\n";

pub fn main() !void {
    try Tls.init();

    const server_fd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(server_fd);

    const port = std.mem.bigToNative(u16, 8000);
    var addr = posix.sockaddr.in{ .family = posix.AF.INET, .addr = 0, .port = port };
    var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.in);

    try posix.bind(server_fd, @ptrCast(@alignCast(&addr)), addr_len);
    try posix.listen(server_fd, config.max_pending_connections);

    while (true) {
        const client_fd = posix.accept(server_fd, @ptrCast(@alignCast(&addr)), &addr_len, 0) catch |err| {
            switch (err) {
                // There's nothing you can do here, it just won't compile
                error.SocketNotListening => break,
                else => return err,
            }
        };
        defer posix.close(@intCast(client_fd));

        std.log.info("connection", .{});

        var req_buf: [config.max_request_size]u8 = undefined;
        const read_bytes = try posix.read(@intCast(client_fd), &req_buf);

        var res_buf: [config.max_response_size]u8 = undefined;

        const request = http.Request.parse(req_buf[0..read_bytes]) catch {
            _ = try posix.write(@intCast(client_fd), response_bad_request);
            continue;
        };

        const zigfile = stdx.cutPrefix(u8, request.path, "/") orelse {
            _ = try posix.write(@intCast(client_fd), response_not_found);
            continue;
        };

        const tarball = backendZig.Tarball.parse(zigfile) catch {
            _ = try posix.write(@intCast(client_fd), response_not_found);
            continue;
        };

        var buffer: [128:0]u8 = undefined;
        const uri = try std.Uri.parse(try tarball.getUpstreamUri(&buffer));

        const stat = std.fs.cwd().statFile(tarball.filename) catch |err| switch (err) {
            error.FileNotFound => blk: {
                const file = try std.fs.cwd().createFile(tarball.filename, .{ .exclusive = true });
                defer file.close();

                try Tls.download(uri, file);

                break :blk try std.fs.cwd().statFile(tarball.filename);
            },
            else => return err,
        };

        const file2 = try std.fs.cwd().openFile(tarball.filename, .{ .mode = .read_only });
        defer file2.close();

        const response = try std.fmt.bufPrintZ(&res_buf, response_ok, .{stat.size});
        const sent_bytes = try posix.write(@intCast(client_fd), response);
        if (sent_bytes < 0) {
            std.log.err("coudn't write all message", .{});
        }

        while (true) {
            var rbuf: [512:0]u8 = undefined;
            const n = try file2.read(&rbuf);
            if (n <= 0) break;

            const bytes = try posix.write(@intCast(client_fd), rbuf[0..@intCast(n)]);
            if (bytes < 0) {
                std.log.err("coudn't write all message", .{});
            }
        }
    }
}

const Tls = struct {
    pub fn init() !void {
        _ = openssl.OPENSSL_init_ssl(openssl.OPENSSL_INIT_LOAD_SSL_STRINGS | openssl.OPENSSL_INIT_LOAD_CRYPTO_STRINGS, null);
        _ = openssl.OPENSSL_init_crypto(openssl.OPENSSL_INIT_ADD_ALL_CIPHERS | openssl.OPENSSL_INIT_ADD_ALL_DIGESTS, null);
    }

    pub const ConnectError = error{
        InvalidUrl,
        OpensslError,
    };

    pub fn download(uri: std.Uri, file: std.fs.File) !void {
        assert(std.mem.eql(u8, "https", uri.scheme));

        var pathbuf: [64:0]u8 = undefined;
        var hostbuf: [64:0]u8 = undefined;
        var hostport: [64:0]u8 = undefined;

        const port = uri.port orelse 443;
        const path = blk: {
            var writer = std.Io.Writer.fixed(&pathbuf);
            try uri.path.formatHost(&writer);
            break :blk writer.buffered();
        };
        const host = blk: {
            if (uri.host) |it| {
                var writer = std.Io.Writer.fixed(&hostbuf);
                try it.formatHost(&writer);
                break :blk writer.buffered();
            } else {
                return error.InvalidUrl;
            }
        };

        _ = try std.fmt.bufPrintZ(&hostport, "{s}:{d}", .{ host, port });

        var buffer: [4096]u8 = undefined;

        const ctx = openssl.SSL_CTX_new(openssl.TLS_client_method()) orelse
            return error.OpensslError;
        defer openssl.SSL_CTX_free(ctx);

        const bio = openssl.BIO_new_ssl_connect(ctx) orelse
            return error.OpensslError;
        defer openssl.BIO_free_all(bio);

        var ssl: ?*openssl.SSL = null;
        _ = openssl.BIO_get_ssl(bio, &ssl);
        if (ssl == null) {
            return error.OpensslError;
        }
        _ = openssl.SSL_set_mode(ssl, openssl.SSL_MODE_AUTO_RETRY);

        _ = openssl.BIO_ctrl(bio, openssl.BIO_C_SET_CONNECT, 0, &hostport[0]);
        if (openssl.BIO_do_connect(bio) <= 0) {
            return error.OpensslError;
        }
        if (openssl.BIO_do_handshake(bio) <= 0) {
            return error.OpensslError;
        }

        {
            const request =
                "GET {s} HTTP/1.1\r\n" ++
                "Host: {s}\r\n" ++
                "Connection: close\r\n" ++
                "\r\n";

            var req: [512:0]u8 = undefined;
            const buf = try std.fmt.bufPrintZ(&req, request, .{ path, host });

            _ = openssl.BIO_write(bio, buf.ptr, @intCast(buf.len));
        }

        var skipped = false;
        while (true) {
            const len = openssl.BIO_read(bio, &buffer[0], 4096);
            if (len <= 0) break;

            if (skipped) {
                _ = try file.write(buffer[0..@intCast(len)]);
            } else {
                if (std.mem.indexOf(u8, buffer[0..@intCast(len)], "\r\n\r\n")) |pos| {
                    std.log.debug("Skipped: {d}!", .{pos});
                    _ = try file.write(buffer[pos + 4 .. @intCast(len)]);
                    skipped = true;
                }
            }
        }
    }
};
