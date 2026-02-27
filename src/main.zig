const std = @import("std");
const quiver = @import("quiver");

pub const std_options: std.Options = .{
    .fmt_max_depth = 64, // Default is usually 16
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const ast_alloc = arena.allocator();

    const source = "( add )b mul )";

    var lines = try quiver.lang.lex(allocator, source);
    std.debug.print("lines: {}\n", .{lines});

    defer {
        for (lines.items) |*line| line.deinit(allocator);
        lines.deinit(allocator);
    }

    var parser = quiver.lang.Parser.init(ast_alloc, source, lines.items);
    defer parser.deinit();
    const file_ast = try parser.parseFile(ast_alloc);

    const main_arity = switch (file_ast.main.*) {
        .func => |f| @tagName(f.arity),
        .value => "value",
    };
    std.debug.print("Parsed {d} constants; main arity: {s}\n{any}\n", .{
        file_ast.consts.len,
        main_arity,
        file_ast.main,
    });
}
