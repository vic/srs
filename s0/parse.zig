//! srs-core parser: tokens -> ast.Decl list.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lex.zig");

pub const Error = error{ Parse, OutOfMemory };

pub const Parser = struct {
    toks: []const lex.Tok,
    a: std.mem.Allocator,
    i: usize = 0,
    err_line: u32 = 0,
    err_msg: []const u8 = "",

    fn peek(p: *Parser) lex.Tok {
        return p.toks[p.i];
    }
    fn peekAt(p: *Parser, k: usize) lex.Tok {
        return p.toks[@min(p.i + k, p.toks.len - 1)];
    }
    fn next(p: *Parser) lex.Tok {
        const t = p.toks[p.i];
        if (t.tag != .eof) p.i += 1;
        return t;
    }
    fn fail(p: *Parser, msg: []const u8) Error {
        p.err_line = p.peek().line;
        p.err_msg = msg;
        return error.Parse;
    }
    fn is(p: *Parser, text: []const u8) bool {
        const t = p.peek();
        return (t.tag == .op or t.tag == .ident) and std.mem.eql(u8, t.text, text);
    }
    fn eat(p: *Parser, text: []const u8) bool {
        if (!p.is(text)) return false;
        _ = p.next();
        return true;
    }
    fn expect(p: *Parser, text: []const u8) Error!void {
        if (!p.eat(text)) return p.fail(text);
    }
    fn expectTag(p: *Parser, tag: lex.Tag) Error!lex.Tok {
        if (p.peek().tag != tag) return p.fail(@tagName(tag));
        return p.next();
    }
    fn ident(p: *Parser) Error![]const u8 {
        return (try p.expectTag(.ident)).text;
    }
    fn new(p: *Parser, e: ast.Expr) Error!*ast.Expr {
        const r = try p.a.create(ast.Expr);
        r.* = e;
        return r;
    }

    pub fn file(p: *Parser) Error![]ast.Decl {
        var ds: std.ArrayList(ast.Decl) = .empty;
        while (true) {
            while (p.peek().tag == .nl) _ = p.next();
            if (p.peek().tag == .eof) break;
            try ds.append(p.a, try p.decl());
        }
        return ds.items;
    }

    fn decl(p: *Parser) Error!ast.Decl {
        if (p.eat("extern")) return .{ .ext = try p.func(false) };
        if (p.is("def")) return .{ .def = try p.func(true) };
        if (p.eat("enum")) {
            const name = try p.ident();
            var cs: std.ArrayList(ast.Case) = .empty;
            try p.layoutOpen();
            while (!p.eatDedent()) {
                try p.expect("case");
                const cn = try p.ident();
                const fs: []ast.Param = if (p.is("(")) try p.params() else &.{};
                try cs.append(p.a, .{ .name = cn, .fields = fs });
                try p.endLine();
            }
            return .{ .enum_ = .{ .name = name, .cases = cs.items } };
        }
        if (p.eat("protocol")) return .{ .proto = try p.protocol() };
        if (p.eat("handler")) {
            const name = try p.ident();
            try p.expect("for");
            const proto = try p.ident();
            var fs: std.ArrayList(ast.Fn) = .empty;
            try p.layoutOpen();
            while (!p.eatDedent()) {
                try fs.append(p.a, try p.func(true));
                if (p.peek().tag == .nl) _ = p.next();
            }
            return .{ .handler = .{ .name = name, .proto = proto, .fns = fs.items } };
        }
        return p.fail("declaration");
    }

    /// `:` nl indent
    fn layoutOpen(p: *Parser) Error!void {
        try p.expect(":");
        _ = try p.expectTag(.nl);
        _ = try p.expectTag(.indent);
    }
    fn eatDedent(p: *Parser) bool {
        if (p.peek().tag != .dedent) return false;
        _ = p.next();
        return true;
    }
    fn endLine(p: *Parser) Error!void {
        if (p.peek().tag == .dedent) return;
        _ = try p.expectTag(.nl);
    }

    fn protocol(p: *Parser) Error!ast.Proto {
        const name = try p.ident();
        var pr: ast.Proto = .{ .name = name, .states = &.{}, .start = "", .ends = &.{}, .ops = &.{}, .drop = null };
        var ops: std.ArrayList(ast.Op) = .empty;
        try p.layoutOpen();
        while (!p.eatDedent()) {
            if (p.eat("state")) {
                pr.states = try p.idents();
            } else if (p.eat("start")) {
                pr.start = try p.ident();
            } else if (p.eat("end")) {
                pr.ends = try p.idents();
            } else if (p.eat("drop")) {
                pr.drop = try p.ident();
            } else if (p.eat("op")) {
                const on = try p.ident();
                const ps = try p.params();
                try p.expect(":");
                const ret = try p.ty();
                try p.expect(":");
                var ts: std.ArrayList(ast.Trans) = .empty;
                while (true) {
                    const f = try p.ident();
                    try p.expect("-");
                    try p.expect(">");
                    try ts.append(p.a, .{ .from = f, .to = try p.ident() });
                    if (!p.eat(",")) break;
                }
                try ops.append(p.a, .{ .name = on, .params = ps, .ret = ret, .trans = ts.items });
            } else return p.fail("protocol item");
            try p.endLine();
        }
        pr.ops = ops.items;
        return pr;
    }

    fn idents(p: *Parser) Error![]const []const u8 {
        var xs: std.ArrayList([]const u8) = .empty;
        try xs.append(p.a, try p.ident());
        while (p.eat(",")) try xs.append(p.a, try p.ident());
        return xs.items;
    }

    fn func(p: *Parser, has_body: bool) Error!ast.Fn {
        const line = p.peek().line;
        try p.expect("def");
        const name = try p.ident();
        const ps = try p.params();
        try p.expect(":");
        const ret = try p.ty();
        var body: ?*ast.Expr = null;
        if (has_body) {
            try p.expect("=");
            body = try p.rhs();
        }
        return .{ .name = name, .params = ps, .ret = ret, .body = body, .line = line };
    }

    fn params(p: *Parser) Error![]ast.Param {
        var ps: std.ArrayList(ast.Param) = .empty;
        try p.expect("(");
        while (!p.eat(")")) {
            const n = try p.ident();
            try p.expect(":");
            try ps.append(p.a, .{ .name = n, .ty = try p.ty() });
            if (!p.is(")")) try p.expect(",");
        }
        return ps.items;
    }

    fn ty(p: *Parser) Error!ast.Type {
        var t: ast.Type = .{ .name = try p.ident() };
        if (p.eat("[")) {
            t.st_from = try p.ident();
            t.st_to = t.st_from;
            if (p.eat("~>")) t.st_to = try p.ident();
            try p.expect("]");
        }
        if (p.eat("^")) {
            try p.expect("{");
            var cs: std.ArrayList([]const u8) = .empty;
            while (!p.eat("}")) {
                try cs.append(p.a, try p.ident());
                if (!p.is("}")) try p.expect(",");
            }
            t.caps = cs.items;
        }
        return t;
    }

    /// expression on the same line, or nl + indented block.
    fn rhs(p: *Parser) Error!*ast.Expr {
        if (p.peek().tag == .nl and p.peekAt(1).tag == .indent) {
            _ = p.next();
            return p.block();
        }
        return p.expr();
    }

    fn block(p: *Parser) Error!*ast.Expr {
        _ = try p.expectTag(.indent);
        var ss: std.ArrayList(ast.Stmt) = .empty;
        while (!p.eatDedent()) {
            try ss.append(p.a, try p.stmt());
            if (p.peek().tag == .nl) _ = p.next();
        }
        var last: ?*ast.Expr = null;
        if (ss.items.len > 0 and ss.items[ss.items.len - 1] == .expr) {
            last = ss.items[ss.items.len - 1].expr;
            ss.items.len -= 1;
        }
        return p.new(.{ .block = .{ .stmts = ss.items, .last = last } });
    }

    fn stmt(p: *Parser) Error!ast.Stmt {
        if (p.is("val") or p.is("var")) {
            const mutable = std.mem.eql(u8, p.next().text, "var");
            const n = try p.ident();
            var t: ?ast.Type = null;
            if (p.eat(":")) t = try p.ty();
            try p.expect("=");
            return .{ .val = .{ .name = n, .ty = t, .e = try p.rhs(), .mutable = mutable } };
        }
        if (p.eat("handle")) {
            const n = try p.ident();
            try p.expect("=");
            const h = try p.ident();
            return .{ .handle = .{ .name = n, .handler = h, .args = try p.args() } };
        }
        return .{ .expr = try p.expr() };
    }

    fn args(p: *Parser) Error![]*ast.Expr {
        var xs: std.ArrayList(*ast.Expr) = .empty;
        try p.expect("(");
        while (!p.eat(")")) {
            try xs.append(p.a, try p.expr());
            if (!p.is(")")) try p.expect(",");
        }
        return xs.items;
    }

    pub fn expr(p: *Parser) Error!*ast.Expr {
        if (p.eat("if")) {
            const c = try p.expr();
            try p.expect("then");
            const t = try p.rhs();
            if (p.peek().tag == .nl and p.peekAt(1).tag == .ident and std.mem.eql(u8, p.peekAt(1).text, "else")) _ = p.next();
            try p.expect("else");
            return p.new(.{ .if_ = .{ .c = c, .t = t, .e = try p.rhs() } });
        }
        if (p.eat("while")) {
            const c = try p.expr();
            try p.expect("do");
            return p.new(.{ .while_ = .{ .c = c, .body = try p.rhs() } });
        }
        if (p.peek().tag == .ident and p.peekAt(1).tag == .op and std.mem.eql(u8, p.peekAt(1).text, "=")) {
            const n = p.next().text;
            _ = p.next();
            return p.new(.{ .assign = .{ .name = n, .e = try p.rhs() } });
        }
        const e = try p.binary(0);
        if (!p.eat("match")) return e;
        _ = try p.expectTag(.nl);
        _ = try p.expectTag(.indent);
        var arms: std.ArrayList(ast.Arm) = .empty;
        while (!p.eatDedent()) {
            try p.expect("case");
            var ctor: ?[]const u8 = null;
            var binds: std.ArrayList([]const u8) = .empty;
            if (!p.eat("_")) {
                ctor = try p.ident();
                if (p.eat("(")) {
                    while (!p.eat(")")) {
                        try binds.append(p.a, try p.ident());
                        if (!p.is(")")) try p.expect(",");
                    }
                }
            }
            try p.expect("=>");
            try arms.append(p.a, .{ .ctor = ctor, .binds = binds.items, .body = try p.rhs() });
            if (p.peek().tag == .nl) _ = p.next();
        }
        return p.new(.{ .match = .{ .scrut = e, .arms = arms.items } });
    }

    const levels = [_][]const []const u8{
        &.{"||"}, &.{"&&"}, &.{ "==", "!=" }, &.{ "<", "<=", ">", ">=" }, &.{ "+", "-" }, &.{ "*", "/", "%" },
    };

    fn binary(p: *Parser, lvl: usize) Error!*ast.Expr {
        if (lvl == levels.len) return p.unary();
        var l = try p.binary(lvl + 1);
        outer: while (p.peek().tag == .op) {
            for (levels[lvl]) |o| {
                if (std.mem.eql(u8, p.peek().text, o)) {
                    _ = p.next();
                    const r = try p.binary(lvl + 1);
                    l = try p.new(.{ .bin = .{ .op = o, .l = l, .r = r } });
                    continue :outer;
                }
            }
            break;
        }
        return l;
    }

    fn unary(p: *Parser) Error!*ast.Expr {
        if (p.eat("-")) return p.new(.{ .un = .{ .op = "-", .e = try p.unary() } });
        if (p.eat("!")) return p.new(.{ .un = .{ .op = "!", .e = try p.unary() } });
        return p.primary();
    }

    fn primary(p: *Parser) Error!*ast.Expr {
        const t = p.peek();
        switch (t.tag) {
            .int => {
                _ = p.next();
                return p.new(.{ .int = std.fmt.parseInt(i64, t.text, 10) catch return p.fail("int literal") });
            },
            .str => {
                _ = p.next();
                return p.new(.{ .str = t.text });
            },
            .char => {
                _ = p.next();
                return p.new(.{ .int = try p.charValue(t.text) });
            },
            .ident => {
                _ = p.next();
                if (std.mem.eql(u8, t.text, "true")) return p.new(.{ .boolean = true });
                if (std.mem.eql(u8, t.text, "false")) return p.new(.{ .boolean = false });
                if (p.is("(")) return p.new(.{ .call = .{ .callee = t.text, .args = try p.args() } });
                if (p.eat(".")) {
                    const op = try p.ident();
                    return p.new(.{ .method = .{ .recv = t.text, .op = op, .args = try p.args() } });
                }
                return p.new(.{ .name = t.text });
            },
            .op => if (p.eat("(")) {
                if (p.eat(")")) return p.new(.unit);
                const e = try p.expr();
                try p.expect(")");
                return e;
            },
            else => {},
        }
        return p.fail("expression");
    }

    fn charValue(p: *Parser, s: []const u8) Error!i64 {
        if (s.len == 1) return s[0];
        if (s.len == 2 and s[0] == '\\') return switch (s[1]) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            '0' => 0,
            '\\' => '\\',
            '\'' => '\'',
            '"' => '"',
            else => p.fail("char escape"),
        };
        return p.fail("char literal");
    }
};
