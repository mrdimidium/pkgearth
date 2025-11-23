//! A set of independent utilities and containers.
//! The types described here should not allocate memory, store it, or handle IO.

const std = @import("std");
const assert = std.debug.assert;

/// Returns a pointer with a lower address.
pub fn minPtr(comptime T: type, a: T, b: T) T {
    return if (@intFromPtr(a) < @intFromPtr(b)) a else b;
}
/// Returns a pointer to the larger address.
pub fn maxPtr(comptime T: type, a: T, b: T) T {
    return if (@intFromPtr(a) > @intFromPtr(b)) a else b;
}

/// Checks that the child slice is completely nested within the parent slice.
pub fn checkSliceNested(comptime T: type, parent: []const T, child: []const T) bool {
    return @intFromPtr(parent.ptr) <= @intFromPtr(child.ptr) and
        @intFromPtr(parent.ptr + parent.len) >= @intFromPtr(child.ptr + child.len);
}

/// Accepts three slices: a parent slice and two slices within it.
/// Returns a new slice that completely overlaps both child slices (and everything in between).
pub fn overlapSlices(comptime T: type, parent: []const T, a: []const T, b: []const T) []const T {
    assert(checkSliceNested(T, parent, a));
    assert(checkSliceNested(T, parent, b));

    const bgn = minPtr([*]const T, a.ptr, b.ptr);
    const end = maxPtr([*]const T, a.ptr + a.len, b.ptr + b.len);

    return bgn[0 .. end - bgn];
}

test "overlapSlices" {
    const buf: []const u8 = "Lorem Ipsum is simply";

    // a to the left of b, do not overlap
    try std.testing.expectEqualStrings(
        "Lorem Ipsum",
        overlapSlices(u8, buf, buf[0..4], buf[6..11]),
    );
    try std.testing.expectEqualStrings(
        "is simply",
        overlapSlices(u8, buf, buf[12..14], buf[15..21]),
    );

    // a to the right of b, do not overlap
    try std.testing.expectEqualStrings(
        "Lorem Ipsum",
        overlapSlices(u8, buf, buf[6..11], buf[0..4]),
    );
    try std.testing.expectEqualStrings(
        "is simply",
        overlapSlices(u8, buf, buf[15..21], buf[12..14]),
    );

    // a inside b
    try std.testing.expectEqualStrings(
        "Ipsum",
        overlapSlices(u8, buf, buf[9..10], buf[6..11]),
    );

    // b inside a
    try std.testing.expectEqualStrings(
        "Ipsum",
        overlapSlices(u8, buf, buf[6..11], buf[9..10]),
    );

    // a and b overlas
    try std.testing.expectEqualStrings(
        "Lorem Ipsum",
        overlapSlices(u8, buf, buf[0..7], buf[5..11]),
    );
    try std.testing.expectEqualStrings(
        "Lorem Ipsum",
        overlapSlices(u8, buf, buf[5..11], buf[0..7]),
    );
}

/// If `slice` starts with `prefix`, returns the rest of `slice` starting at `prefix.len`.
pub fn cutPrefix(comptime T: type, slice: []const T, prefix: []const T) ?[]const T {
    return if (std.mem.startsWith(T, slice, prefix)) slice[prefix.len..] else null;
}

test cutPrefix {
    try std.testing.expectEqualStrings("foo", cutPrefix(u8, "--example=foo", "--example=").?);
    try std.testing.expectEqual(null, cutPrefix(u8, "--example=foo", "-example="));
}

/// If `slice` ends with `suffix`, returns `slice` from beginning to start of `suffix`.
pub fn cutSuffix(comptime T: type, slice: []const T, suffix: []const T) ?[]const T {
    return if (std.mem.endsWith(T, slice, suffix)) slice[0 .. slice.len - suffix.len] else null;
}

test cutSuffix {
    try std.testing.expectEqualStrings("foo", cutSuffix(u8, "foobar", "bar").?);
    try std.testing.expectEqual(null, cutSuffix(u8, "foobar", "baz"));
}
