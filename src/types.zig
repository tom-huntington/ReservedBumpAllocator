const std = @import("std");

pub const TokenTag = enum {
    ident,
    combinator,
    number,
    char_lit,
    raw_string,
    comma,
    caret,
    underscore,
    pipe_gt,
    lparen,
    rparen,
    lbrace,
    rbrace,
    backslash,
    dbl_backslash,
    equal,
};

pub const Token = struct {
    tag: TokenTag,
    start: usize,
    end: usize,

    pub fn lexeme(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

pub const Arity = enum { value, monad, dyad };

pub const Value = union(enum) {
    scalar: struct { value: f64, is_char: bool },
    array: struct { data: []f64, shape: []u32, is_char: bool },
    ident: []const u8,
};

pub const MonadFn = *const fn (std.mem.Allocator, Value) Value;
pub const DyadFn = *const fn (std.mem.Allocator, Value, Value) Value;

pub const Combinator = enum {
    B,
    B1,
    S,
    Sig,
    D,
    Delta,
    Phi,
    Psi,
    D1,
    D2,
    N,
    V,
    X,
    Xi,
    Phi1,
};

pub const PartialApply = enum { comma, caret };

pub const Expr = union(enum) {
    value: ValueUnion,
    func: FuncUnion,

    pub const FuncUnion = struct {
        arity: Arity,
        type: union(enum) {
            combinator: struct { op: Combinator, left: *FuncUnion, right: *FuncUnion },
            partial_apply: struct { op: PartialApply, left: *FuncUnion, right: *FuncUnion },
            scope: *FuncUnion,
            userFn: *FuncUnion,
            builtin: union(enum) { monad: MonadFn, dyad: DyadFn },
        },
    };

    pub const ValueUnion = union(enum) {
        literal: Value,
        strand: struct { left: *Expr, right: *Expr },
        apply_rev: struct { func: *Expr, arg: *Expr },
    };
};
