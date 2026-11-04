//! S0: `s0 a.srs b.srs ... > out.c`. Decls of all files form one program.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lex.zig");
const parse = @import("parse.zig");
const emit = @import("emit.zig");

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const argv = try init.minimal.args.toSlice(a);
    const stderr = std.Io.File.stderr();
    var decls: std.ArrayList(ast.Decl) = .empty;
    // `-t file`: token dump, the S1 lexer oracle.
    const dump = argv.len == 3 and std.mem.eql(u8, argv[1], "-t");
    for (argv[if (dump) 2 else 1..]) |path| {
        const src = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .unlimited);
        var lx: lex.Lexer = .{ .src = src };
        const toks = lx.run(a) catch |err| {
            try stderr.writeStreamingAll(io, try std.fmt.allocPrint(a, "{s}:{d}: lex error: {s}\n", .{ path, lx.err_line, lx.err_msg }));
            return err;
        };
        if (dump) {
            var out: std.ArrayList(u8) = .empty;
            for (toks) |t| try out.print(a, "{d} {s} {s}\n", .{ t.line, @tagName(t.tag), t.text });
            return std.Io.File.stdout().writeStreamingAll(io, out.items);
        }
        var p: parse.Parser = .{ .toks = toks, .a = a };
        const ds = p.file() catch |err| {
            const t = p.toks[p.i];
            try stderr.writeStreamingAll(io, try std.fmt.allocPrint(a, "{s}:{d}: parse error: expected {s}, got '{s}' ({s})\n", .{ path, p.err_line, p.err_msg, t.text, @tagName(t.tag) }));
            return err;
        };
        try decls.appendSlice(a, ds);
    }
    var e: emit.Emitter = .{ .a = a };
    const c = e.program(decls.items) catch |err| {
        try stderr.writeStreamingAll(io, try std.fmt.allocPrint(a, "emit error: {s} '{s}'\n", .{ e.err_msg, e.err_name }));
        return err;
    };
    try std.Io.File.stdout().writeStreamingAll(io, c);
}

test {
    _ = lex;
    _ = parse;
    _ = emit;
}
