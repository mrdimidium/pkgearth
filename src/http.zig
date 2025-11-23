const std = @import("std");

/// HTTP protocol version
pub const Version = enum { @"HTTP/1.0", @"HTTP/1.1" };

/// HTTP defines a set of request methods to indicate the purpose
/// of the request and what is expected if the request is successful
///
/// https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods
pub const Method = enum {
    // requests a representation of the specified resource.
    // Requests using GET should only retrieve data and should not contain a request content.
    GET,

    // asks for a response identical to a GET request,
    // but without a response body.
    HEAD,

    // submits an entity to the specified resource,
    // often causing a change in state or side effects on the server.
    POST,

    // replaces all current representations of the target resource with the request content.
    PUT,

    // deletes the specified resource.
    DELETE,

    // establishes a tunnel to the server identified by the target resource.
    CONNECT,

    // describes the communication options for the target resource.
    OPTIONS,

    // performs a message loop-back test along the path to the target resource.
    TRACE,

    // applies partial modifications to a resource.
    PATCH,

    pub fn fromString(str: []const u8) ?Method {
        const protocol_map = std.StaticStringMap(Method).initComptime(.{
            .{ "GET", .GET },
            .{ "HEAD", .HEAD },
            .{ "POST", .POST },
            .{ "PUT", .PUT },
            .{ "DELETE", .DELETE },
            .{ "CONNECT", .CONNECT },
            .{ "OPTIONS", .OPTIONS },
            .{ "TRACE", .TRACE },
            .{ "PATCH", .PATCH },
        });
        return protocol_map.get(str);
    }

    pub fn toString(m: Method) []const u8 {
        return switch (m) {
            .GET => "GET",
            .HEAD => "HEAD",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .CONNECT => "CONNECT",
            .OPTIONS => "OPTIONS",
            .TRACE => "TRACE",
            .PATCH => "PATCH",
        };
    }
};

pub const Request = struct {
    version: Version,
    method: Method,
    path: []const u8,
    body: ?[]const u8 = null,

    pub const ParseError = error{
        UnknownMethod,
        InvalidStartline,
    };

    pub fn parse(payload: []const u8) ParseError!Request {
        var step: enum { startline, headers, body } = .startline;
        var request = Request{ .version = undefined, .method = undefined, .path = "" };

        var it = std.mem.splitSequence(u8, payload, "\r\n");
        while (it.next()) |line| switch (step) {
            .startline => {
                var it2 = std.mem.splitSequence(u8, line, " ");
                if (it2.next()) |method| {
                    request.method =
                        Method.fromString(method) orelse return error.UnknownMethod;
                } else {
                    return error.UnknownMethod;
                }

                if (it2.next()) |path| {
                    if (!std.mem.startsWith(u8, path, "/")) {
                        return error.InvalidStartline;
                    }

                    request.path = path;
                } else {
                    return error.InvalidStartline;
                }

                if (it2.next()) |version| {
                    request.version =
                        if (std.mem.eql(u8, "HTTP/1.0", version))
                            .@"HTTP/1.0"
                        else if (std.mem.eql(u8, "HTTP/1.1", version))
                            .@"HTTP/1.1"
                        else
                            return error.InvalidStartline;
                } else {
                    return error.InvalidStartline;
                }

                if (it2.next() != null) {
                    return error.InvalidStartline;
                }

                step = .headers;
            },
            .headers => {
                if (line.len == 0) {
                    step = .body;
                    continue;
                }
            },
            .body => {
                break;
            },
        };

        return request;
    }
};

pub const Response = struct {};
