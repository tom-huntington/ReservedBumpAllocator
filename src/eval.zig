const std = @import("std");
const parse = @import("parse.zig");
const types = @import("types.zig");
const Expr = types.Expr;
const Value = types.Value;

pub const Args = union(enum) {
    monad: [1]Value,
    dyad: [2]Value,
};

pub const EvalError = error{
    ArityMismatch,
    UnsupportedFunctionKind,
    UnsupportedValueKind,
};

pub fn foldFileConstants(allocator: std.mem.Allocator, file_ast: *parse.FileAst) EvalError!void {
    for (file_ast.consts) |const_def| {
        _ = try foldExpr(allocator, const_def.expr);
    }
    try foldFuncExpr(allocator, file_ast.main);
}

pub fn evalFunc(allocator: std.mem.Allocator, func: *const Expr.FuncExpr, args: Args) EvalError!Value {
    switch (func.type) {
        .builtin => |builtin| switch (builtin) {
            .monad => |f| {
                const monad_args = switch (args) {
                    .monad => |monad_args| monad_args,
                    .dyad => return error.ArityMismatch,
                };
                return f(allocator, monad_args[0]);
            },
            .dyad => |f| {
                const dyad_args = switch (args) {
                    .dyad => |dyad_args| dyad_args,
                    .monad => return error.ArityMismatch,
                };
                return f(allocator, dyad_args[0], dyad_args[1]);
            },
        },
        .scope => |scoped| return evalFunc(allocator, scoped, args),
        .userFn => |user_fn| return evalFunc(allocator, user_fn, args),
        .combinator => |com| {
            switch (com.op) {
                .B1, .B => {
                    const a = try evalFunc(allocator, com.left, args);
                    return evalFunc(allocator, com.right, .{ .monad = .{a} });
                },
                else => {
                    @panic("not implemented");
                },
            }
        },
        .partial_apply => |partial| {
            const right = try evalValueExpr(allocator, partial.right);
            return applyRightArg(allocator, partial.left, args, right);
        },
        .right_partial_apply => |partial| {
            const right = try evalRightFunc(allocator, partial.right, args);
            return applyRightArg(allocator, partial.left, args, right);
        },
    }
}

fn evalExpr(allocator: std.mem.Allocator, expr: *const Expr) EvalError!Value {
    return switch (expr.*) {
        .func => return error.UnsupportedValueKind,
        .value => |*value_expr| evalValueExpr(allocator, value_expr),
    };
}

fn evalValueExpr(allocator: std.mem.Allocator, expr: *const Expr.ValueExpr) EvalError!Value {
    return switch (expr.*) {
        .literal => |literal| literal,
        .strand => |strand| evalStrand(allocator, strand.left, strand.right),
        .apply => |apply| {
            const func = switch (apply.func.*) {
                .func => |*func| func,
                .value => return error.UnsupportedValueKind,
            };
            return evalFunc(allocator, func, try evalArgs(allocator, apply.arg));
        },
    };
}

fn foldExpr(allocator: std.mem.Allocator, expr: *Expr) EvalError!bool {
    switch (expr.*) {
        .func => {
            try foldFuncExpr(allocator, &expr.func);
            return false;
        },
        .value => {
            const value = try foldValueExpr(allocator, &expr.value);
            expr.* = .{ .value = .{ .literal = value } };
            return true;
        },
    }
}

fn foldFuncExpr(allocator: std.mem.Allocator, func: *Expr.FuncExpr) EvalError!void {
    switch (func.type) {
        .builtin => {},
        .scope => |scoped| try foldFuncExpr(allocator, scoped),
        .userFn => |user_fn| try foldFuncExpr(allocator, user_fn),
        .combinator => |com| {
            try foldFuncExpr(allocator, com.left);
            try foldFuncExpr(allocator, com.right);
        },
        .partial_apply => |partial| {
            const value = try foldValueExpr(allocator, partial.right);
            partial.right.* = .{ .literal = value };
            try foldFuncExpr(allocator, partial.left);
        },
        .right_partial_apply => |partial| {
            try foldFuncExpr(allocator, partial.left);
            try foldFuncExpr(allocator, partial.right);
        },
    }
}

fn foldValueExpr(allocator: std.mem.Allocator, expr: *Expr.ValueExpr) EvalError!Value {
    switch (expr.*) {
        .literal => {},
        .strand => |strand| {
            _ = try foldExpr(allocator, strand.left);
            _ = try foldExpr(allocator, strand.right);
        },
        .apply => |apply| {
            _ = try foldExpr(allocator, apply.func);
            _ = try foldExpr(allocator, apply.arg);
        },
    }
    return evalValueExpr(allocator, expr);
}

fn evalArgs(allocator: std.mem.Allocator, expr: *const Expr) EvalError!Args {
    return switch (expr.*) {
        .func => return error.UnsupportedValueKind,
        .value => |value_expr| switch (value_expr) {
            .literal, .apply => .{ .monad = .{try evalExpr(allocator, expr)} },
            .strand => |strand| .{
                .dyad = .{
                    try evalExpr(allocator, strand.left),
                    try evalExpr(allocator, strand.right),
                },
            },
        },
    };
}

fn evalRightFunc(allocator: std.mem.Allocator, func: *const Expr.FuncExpr, args: Args) EvalError!Value {
    return switch (args) {
        .monad => |monad_args| evalFunc(allocator, func, .{ .monad = monad_args }),
        .dyad => |dyad_args| switch (func.arity) {
            .dyad => evalFunc(allocator, func, .{ .dyad = dyad_args }),
            .monad => evalFunc(allocator, func, .{ .monad = .{dyad_args[1]} }),
            .value => error.ArityMismatch,
        },
    };
}

fn applyRightArg(
    allocator: std.mem.Allocator,
    func: *const Expr.FuncExpr,
    args: Args,
    right: Value,
) EvalError!Value {
    return switch (func.arity) {
        .monad => evalFunc(allocator, func, .{ .monad = .{right} }),
        .dyad => {
            const dyad_args = switch (args) {
                .dyad => |dyad_args| dyad_args,
                .monad => return error.ArityMismatch,
            };
            return evalFunc(allocator, func, .{ .dyad = .{ dyad_args[0], right } });
        },
        .value => error.ArityMismatch,
    };
}

fn evalStrand(allocator: std.mem.Allocator, left: *const Expr, right: *const Expr) EvalError!Value {
    var items: std.ArrayList(Value) = .empty;
    defer items.deinit(allocator);

    try appendStrandItems(allocator, &items, left);
    try appendStrandItems(allocator, &items, right);
    return materializeArrayStrand(allocator, items.items);
}

fn appendStrandItems(allocator: std.mem.Allocator, items: *std.ArrayList(Value), expr: *const Expr) EvalError!void {
    switch (expr.*) {
        .func => return error.UnsupportedValueKind,
        .value => |value_expr| switch (value_expr) {
            .strand => |strand| {
                try appendStrandItems(allocator, items, strand.left);
                try appendStrandItems(allocator, items, strand.right);
            },
            else => items.append(allocator, try evalValueExpr(allocator, &value_expr)) catch @panic("out of memory"),
        },
    }
}

fn materializeArrayStrand(allocator: std.mem.Allocator, items: []const Value) EvalError!Value {
    if (items.len == 0) return error.UnsupportedValueKind;

    const first_shape = switch (items[0]) {
        .scalar => &[_]u32{},
        .array => |array| array.shape,
        .ident => return error.UnsupportedValueKind,
    };
    const elem_len = switch (items[0]) {
        .scalar => @as(usize, 1),
        .array => |array| array.data.len,
        .ident => unreachable,
    };

    var is_char = switch (items[0]) {
        .scalar => |scalar| scalar.is_char,
        .array => |array| array.is_char,
        .ident => unreachable,
    };

    for (items[1..]) |item| {
        switch (item) {
            .scalar => {
                if (first_shape.len != 0) return error.UnsupportedValueKind;
                is_char = is_char and item.scalar.is_char;
            },
            .array => |array| {
                if (!std.mem.eql(u32, first_shape, array.shape)) return error.UnsupportedValueKind;
                if (array.data.len != elem_len) return error.UnsupportedValueKind;
                is_char = is_char and array.is_char;
            },
            .ident => return error.UnsupportedValueKind,
        }
    }

    const data = allocator.alloc(f64, items.len * elem_len) catch @panic("out of memory");
    const shape = allocator.alloc(u32, first_shape.len + 1) catch @panic("out of memory");
    shape[0] = @intCast(items.len);
    @memcpy(shape[1..], first_shape);

    var data_index: usize = 0;
    for (items) |item| {
        switch (item) {
            .scalar => |scalar| {
                data[data_index] = scalar.value;
                data_index += 1;
            },
            .array => |array| {
                @memcpy(data[data_index .. data_index + array.data.len], array.data);
                data_index += array.data.len;
            },
            .ident => return error.UnsupportedValueKind,
        }
    }

    return .{ .array = .{ .data = data, .shape = shape, .is_char = is_char } };
}

test "eval comma partial application fixes the right argument" {
    const allocator = std.testing.allocator;
    const source = "add,3";

    var lexed = try @import("lex.zig").lex(allocator, source);
    defer lexed.deinit(allocator);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = @import("parse.zig").Parser.init(arena.allocator(), source, lexed.tokens.items, lexed.line_offsets.items);
    defer parser.deinit();
    const file_ast = try parser.parseFile(arena.allocator());

    const result = try evalFunc(arena.allocator(), file_ast.main, .{
        .dyad = .{
            .{ .scalar = .{ .value = 2, .is_char = false } },
            .{ .scalar = .{ .value = 99, .is_char = false } },
        },
    });

    try std.testing.expectEqual(@as(Value.Tag, .scalar), result);
    try std.testing.expectEqual(@as(f64, 5), result.scalar.value);
}

test "eval caret partial application transforms the right argument" {
    const allocator = std.testing.allocator;
    const source = "add^sq";

    var lexed = try @import("lex.zig").lex(allocator, source);
    defer lexed.deinit(allocator);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = @import("parse.zig").Parser.init(arena.allocator(), source, lexed.tokens.items, lexed.line_offsets.items);
    defer parser.deinit();
    const file_ast = try parser.parseFile(arena.allocator());

    const result = try evalFunc(arena.allocator(), file_ast.main, .{
        .dyad = .{
            .{ .scalar = .{ .value = 2, .is_char = false } },
            .{ .scalar = .{ .value = 3, .is_char = false } },
        },
    });

    try std.testing.expectEqual(@as(Value.Tag, .scalar), result);
    try std.testing.expectEqual(@as(f64, 11), result.scalar.value);
}

test "eval strand materializes a constant array" {
    const allocator = std.testing.allocator;
    const source = "1_2_3";

    var lexed = try @import("lex.zig").lex(allocator, source);
    defer lexed.deinit(allocator);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = @import("parse.zig").Parser.init(arena.allocator(), source, lexed.tokens.items, lexed.line_offsets.items);
    defer parser.deinit();
    try parser.populateBuiltins();

    var index: usize = 0;
    const expr = try parser.parseExpr(&index, lexed.tokens.items.len, 0, null);

    const result = try evalExpr(arena.allocator(), expr);
    try std.testing.expectEqual(@as(Value.Tag, .array), result);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2, 3 }, result.array.data);
    try std.testing.expectEqualSlices(u32, &.{ 3 }, result.array.shape);
}

test "constant folding rewrites partial application constants before main eval" {
    const allocator = std.testing.allocator;
    const source =
        \\a = 1_1
        \\add,a )b1 sq
    ;

    var lexed = try @import("lex.zig").lex(allocator, source);
    defer lexed.deinit(allocator);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = @import("parse.zig").Parser.init(arena.allocator(), source, lexed.tokens.items, lexed.line_offsets.items);
    defer parser.deinit();
    var file_ast = try parser.parseFile(arena.allocator());

    try foldFileConstants(arena.allocator(), &file_ast);

    try std.testing.expectEqual(@as(Expr.ValueExpr.Tag, .literal), file_ast.consts[0].expr.value);
    try std.testing.expectEqual(@as(Value.Tag, .array), file_ast.consts[0].expr.value.literal);

    const partial = switch (file_ast.main.type) {
        .combinator => |com| switch (com.left.type) {
            .partial_apply => |partial| partial,
            else => return error.UnsupportedFunctionKind,
        },
        else => return error.UnsupportedFunctionKind,
    };

    try std.testing.expectEqual(@as(Expr.ValueExpr.Tag, .literal), partial.right.*);
    try std.testing.expectEqual(@as(Value.Tag, .array), partial.right.literal);
}
