const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

pub fn add(all: std.mem.Allocator, a: Value, b: Value) Value {
    _ = all;

    switch (a) {
        .scalar => |as| {
            switch (b) {
                .scalar => |bs| {
                    const val = as.value + bs.value;
                    return .{ .scalar = .{ .value = val, .is_char = bs.is_char and as.is_char } };
                },
                else => {},
            }
        },
        else => {},
    }
    @panic("not implemented");
}
pub fn mul(all: std.mem.Allocator, a: Value, b: Value) Value {
    _ = a;
    _ = all;
    return b;
}
pub fn sq(all: std.mem.Allocator, a: Value) Value {
    _ = all;
    return a;
}
