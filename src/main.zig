const std = @import("std");
const quiver = @import("quiver");
const stringprint = @import("stringprint.zig");
const lexparse = quiver.lexparse;

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

    const source = "( add )b sq )";
    std.debug.print("soure: {s}\n", .{source});

    var lines = try lexparse.lex(allocator, source);
    stringprint.printfmt("lines: {}\n", .{lines});
    // for (lines.items) |line| {
    //     for (line.items) |tok|
    //         std.debug.print(", {{ .tag={} .text='{s}' }}", .{ tok.tag, source[tok.start..tok.end] });

    //     std.debug.print("\n", .{});
    // }
    //var string: std.io.Writer.Allocating = .init(allocator);
    //try string.writer.print("{f}", .{std.json.fmt(lines, .{})});

    defer {
        for (lines.items) |*line| line.deinit(allocator);
        lines.deinit(allocator);
    }

    var parser = lexparse.Parser.init(ast_alloc, source, lines.items);
    defer parser.deinit();
    const file_ast = try parser.parseFile(ast_alloc);

    stringprint.printfmt("main: {}\n", .{file_ast.main});
}
