//! S0 emitter: ast -> GNU C (statement expressions, __auto_type).
//! S0 trusts its input: checks live in S1 (vic/c/effects.md).
const std = @import("std");
const ast = @import("ast.zig");

pub const Error = error{ Emit, OutOfMemory };

const Ctor = struct { enum_name: []const u8, tag: usize, case: ast.Case };
const Local = struct { name: []const u8, c: []const u8, proto: ?[]const u8 };

pub const Emitter = struct {
    a: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    fns: std.StringHashMapUnmanaged(bool) = .empty, // true = srs def, false = extern
    ctors: std.StringHashMapUnmanaged(Ctor) = .empty,
    enums: std.StringHashMapUnmanaged(void) = .empty,
    protos: std.StringHashMapUnmanaged(ast.Proto) = .empty,
    handlers: std.StringHashMapUnmanaged([]const u8) = .empty, // handler -> protocol
    locals: std.ArrayList(Local) = .empty,
    uniq: u32 = 0,
    err_msg: []const u8 = "",
    err_name: []const u8 = "",

    fn w(e: *Emitter, s: []const u8) Error!void {
        try e.out.appendSlice(e.a, s);
    }
    fn f(e: *Emitter, comptime fmt: []const u8, xs: anytype) Error!void {
        try e.out.print(e.a, fmt, xs);
    }
    fn fail(e: *Emitter, msg: []const u8, name: []const u8) Error {
        e.err_msg = msg;
        e.err_name = name;
        return error.Emit;
    }
    fn fresh(e: *Emitter) u32 {
        e.uniq += 1;
        return e.uniq;
    }

    fn ctype(e: *Emitter, t: ast.Type) Error![]const u8 {
        const n = t.name;
        if (eq(n, "I64") or eq(n, "Unit")) return "int64_t";
        if (eq(n, "Bool")) return "bool";
        if (eq(n, "Str")) return "srs_str";
        if (eq(n, "Ptr")) return "void*";
        if (e.enums.contains(n)) return std.fmt.allocPrint(e.a, "struct E_{s}*", .{n});
        if (e.protos.contains(n)) return "srs_cap*";
        return e.fail("unknown type", n);
    }

    pub fn program(e: *Emitter, ds: []const ast.Decl) Error![]u8 {
        for (ds) |d| switch (d) {
            .ext => |x| try e.fns.put(e.a, x.name, false),
            .def => |x| try e.fns.put(e.a, x.name, true),
            .enum_ => |x| {
                try e.enums.put(e.a, x.name, {});
                for (x.cases, 0..) |c, i| try e.ctors.put(e.a, c.name, .{ .enum_name = x.name, .tag = i, .case = c });
            },
            .proto => |x| try e.protos.put(e.a, x.name, x),
            .handler => |x| try e.handlers.put(e.a, x.name, x.proto),
        };
        try e.w(prelude);
        for (ds) |d| if (d == .enum_) try e.f("struct E_{s};\n", .{d.enum_.name});
        for (ds) |d| if (d == .enum_) try e.enumDef(d.enum_.name, d.enum_.cases);
        for (ds) |d| switch (d) {
            .ext => |x| try e.proto_(x, "", ""),
            .def => |x| try e.proto_(x, "static ", "f_"),
            .handler => |h| for (h.fns) |x| try e.proto_(x, "static ", try std.fmt.allocPrint(e.a, "h_{s}_", .{h.name})),
            else => {},
        };
        for (ds) |d| switch (d) {
            .ext, .def, .enum_, .proto => {},
            .handler => |h| {
                const pr = e.protos.get(h.proto) orelse return e.fail("unknown protocol", h.proto);
                try e.f("static void* const vt_{s}[] = {{", .{h.name});
                for (pr.ops) |op| try e.f(" (void*)h_{s}_{s},", .{ h.name, op.name });
                try e.w(" 0 };\n");
            },
        };
        for (ds) |d| switch (d) {
            .def => |x| try e.body(x, "f_"),
            .handler => |h| for (h.fns) |x| try e.body(x, try std.fmt.allocPrint(e.a, "h_{s}_", .{h.name})),
            else => {},
        };
        if (e.fns.get("main") == true)
            try e.w("int main(int argc, char** argv) { rt_init(argc, argv); return (int)f_main(); }\n");
        return e.out.items;
    }

    fn enumDef(e: *Emitter, name: []const u8, cases: []const ast.Case) Error!void {
        try e.f("struct E_{s} {{ int64_t tag; union {{", .{name});
        for (cases) |c| {
            if (c.fields.len == 0) continue;
            try e.w(" struct {");
            for (c.fields) |fl| try e.f(" {s} f_{s};", .{ try e.ctype(fl.ty), fl.name });
            try e.f(" }} C_{s};", .{c.name});
        }
        try e.w(" int64_t none_; } u; };\n");
        for (cases, 0..) |c, i| if (c.fields.len == 0)
            try e.f("static struct E_{s} N_{s} = {{ {d}, {{ 0 }} }};\n", .{ name, c.name, i });
    }

    fn sig(e: *Emitter, x: ast.Fn, pre: []const u8, prefix: []const u8) Error!void {
        try e.f("{s}{s} {s}{s}(", .{ pre, try e.ctype(x.ret), prefix, x.name });
        for (x.params, 0..) |p, i| {
            if (i > 0) try e.w(", ");
            try e.f("{s} p_{s}", .{ try e.ctype(p.ty), p.name });
        }
        if (x.params.len == 0) try e.w("void");
        try e.w(")");
    }
    fn proto_(e: *Emitter, x: ast.Fn, pre: []const u8, prefix: []const u8) Error!void {
        try e.sig(x, pre, prefix);
        try e.w(";\n");
    }

    fn body(e: *Emitter, x: ast.Fn, prefix: []const u8) Error!void {
        try e.sig(x, "static ", prefix);
        try e.w(" { return ");
        e.locals.items.len = 0;
        for (x.params) |p| try e.locals.append(e.a, .{
            .name = p.name,
            .c = try std.fmt.allocPrint(e.a, "p_{s}", .{p.name}),
            .proto = if (e.protos.contains(p.ty.name)) p.ty.name else null,
        });
        try e.expr(x.body orelse return e.fail("missing body", x.name));
        try e.w("; }\n");
    }

    fn lookup(e: *Emitter, n: []const u8) ?Local {
        var i = e.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (eq(e.locals.items[i].name, n)) return e.locals.items[i];
        }
        return null;
    }

    fn region(e: *Emitter) ?Local {
        var i = e.locals.items.len;
        while (i > 0) {
            i -= 1;
            const l = e.locals.items[i];
            if (l.proto) |p| if (eq(p, "Region")) return l;
        }
        return null;
    }

    fn opIndex(pr: ast.Proto, name: []const u8) ?usize {
        for (pr.ops, 0..) |op, i| if (eq(op.name, name)) return i;
        return null;
    }

    fn args(e: *Emitter, xs: []const *ast.Expr, lead: bool) Error!void {
        for (xs, 0..) |x, i| {
            if (i > 0 or lead) try e.w(", ");
            try e.expr(x);
        }
    }

    fn expr(e: *Emitter, x: *const ast.Expr) Error!void {
        switch (x.*) {
            .int => |v| try e.f("((int64_t){d})", .{v}),
            .boolean => |v| try e.w(if (v) "true" else "false"),
            .unit => try e.w("((int64_t)0)"),
            .str => |s| try e.f("((srs_str){{(const uint8_t*)\"{s}\", {d}}})", .{ s, unescapedLen(s) }),
            .name => |n| {
                if (e.lookup(n)) |l| return e.w(l.c);
                if (e.ctors.get(n)) |c| if (c.case.fields.len == 0)
                    return e.f("(&N_{s})", .{n});
                return e.fail("unknown name", n);
            },
            .call => |c| {
                if (e.ctors.get(c.callee)) |k| return e.ctor(k, c.args);
                const srs = e.fns.get(c.callee) orelse return e.fail("unknown function", c.callee);
                try e.f("{s}{s}(", .{ if (srs) "f_" else "", c.callee });
                try e.args(c.args, false);
                try e.w(")");
            },
            .method => |m| {
                const l = e.lookup(m.recv) orelse return e.fail("unknown capability", m.recv);
                const pn = l.proto orelse return e.fail("not a capability", m.recv);
                const pr = e.protos.get(pn) orelse return e.fail("unknown protocol", pn);
                const k = opIndex(pr, m.op) orelse return e.fail("unknown op", m.op);
                const op = pr.ops[k];
                var kills = op.trans.len > 0;
                for (op.trans) |t| kills = kills and contains(pr.ends, t.to);
                try e.f("({{ __auto_type r_ = (({s}(*)(void*", .{try e.ctype(op.ret)});
                for (op.params) |p| try e.f(", {s}", .{try e.ctype(p.ty)});
                try e.f("))({s}->vt[{d}]))({s}->self", .{ l.c, k, l.c });
                try e.args(m.args, true);
                try e.f("); {s}r_; }})", .{if (kills) try std.fmt.allocPrint(e.a, "{s}->live = 0; ", .{l.c}) else ""});
            },
            .bin => |b| {
                try e.w("(");
                try e.expr(b.l);
                try e.f(" {s} ", .{b.op});
                try e.expr(b.r);
                try e.w(")");
            },
            .un => |u| {
                try e.f("({s}", .{u.op});
                try e.expr(u.e);
                try e.w(")");
            },
            .if_ => |i| {
                try e.w("(");
                try e.expr(i.c);
                try e.w(" ? ");
                try e.expr(i.t);
                try e.w(" : ");
                try e.expr(i.e);
                try e.w(")");
            },
            .match => |m| try e.match(m.scrut, m.arms),
            .block => |b| try e.block(b.stmts, b.last),
            .while_ => |wl| {
                try e.w("({ while (");
                try e.expr(wl.c);
                try e.w(") { (void)(");
                try e.expr(wl.body);
                try e.w("); } (int64_t)0; })");
            },
            .assign => |as| {
                const l = e.lookup(as.name) orelse return e.fail("unknown variable", as.name);
                try e.f("({s} = (", .{l.c});
                try e.expr(as.e);
                try e.w("), (int64_t)0)");
            },
        }
    }

    fn ctor(e: *Emitter, k: Ctor, xs: []const *ast.Expr) Error!void {
        if (xs.len != k.case.fields.len) return e.fail("constructor arity", k.case.name);
        const r = e.region() orelse return e.fail("no Region capability in scope for", k.case.name);
        const pr = e.protos.get("Region") orelse return e.fail("unknown protocol", "Region");
        const ai = opIndex(pr, "alloc") orelse return e.fail("unknown op", "alloc");
        const u = e.fresh();
        try e.f("({{ struct E_{s}* o{d} = (struct E_{s}*)((void*(*)(void*, int64_t))({s}->vt[{d}]))({s}->self, (int64_t)sizeof(struct E_{s})); o{d}->tag = {d};", .{ k.enum_name, u, k.enum_name, r.c, ai, r.c, k.enum_name, u, k.tag });
        for (xs, k.case.fields) |x, fl| {
            try e.f(" o{d}->u.C_{s}.f_{s} = ", .{ u, k.case.name, fl.name });
            try e.expr(x);
            try e.w(";");
        }
        try e.f(" o{d}; }})", .{u});
    }

    fn match(e: *Emitter, scrut: *const ast.Expr, arms: []const ast.Arm) Error!void {
        const u = e.fresh();
        try e.f("({{ __auto_type s{d} = ", .{u});
        try e.expr(scrut);
        try e.w("; ");
        for (arms, 0..) |arm, i| {
            const last = i + 1 == arms.len;
            const mark = e.locals.items.len;
            if (arm.ctor) |cn| {
                const k = e.ctors.get(cn) orelse return e.fail("unknown constructor", cn);
                if (arm.binds.len != k.case.fields.len) return e.fail("pattern arity", cn);
                if (!last) try e.f("s{d}->tag == {d} ? ", .{ u, k.tag });
                try e.w("({ ");
                for (arm.binds, k.case.fields) |b, fl| {
                    if (eq(b, "_")) continue;
                    const c = try std.fmt.allocPrint(e.a, "v_{s}_{d}", .{ b, e.fresh() });
                    try e.f("__auto_type {s} = s{d}->u.C_{s}.f_{s}; ", .{ c, u, cn, fl.name });
                    try e.locals.append(e.a, .{ .name = b, .c = c, .proto = null });
                }
            } else try e.w("({ ");
            try e.expr(arm.body);
            try e.w("; })");
            if (!last) try e.w(" : ");
            e.locals.items.len = mark;
        }
        try e.w("; })");
    }

    fn block(e: *Emitter, stmts: []const ast.Stmt, last: ?*ast.Expr) Error!void {
        const mark = e.locals.items.len;
        var caps: std.ArrayList(Local) = .empty;
        try e.w("({ ");
        for (stmts) |s| switch (s) {
            .expr => |x| {
                try e.w("(void)(");
                try e.expr(x);
                try e.w("); ");
            },
            .val => |v| {
                const c = try std.fmt.allocPrint(e.a, "v_{s}_{d}", .{ v.name, e.fresh() });
                try e.f("{s} {s} = ", .{ if (v.ty) |t| try e.ctype(t) else "__auto_type", c });
                try e.expr(v.e);
                try e.w("; ");
                try e.locals.append(e.a, .{ .name = v.name, .c = c, .proto = null });
            },
            .handle => |h| {
                const pn = e.handlers.get(h.handler) orelse return e.fail("unknown handler", h.handler);
                const c = try std.fmt.allocPrint(e.a, "v_{s}_{d}", .{ h.name, e.fresh() });
                try e.f("srs_cap {s}_v = {{ h_{s}_init(", .{ c, h.handler });
                try e.args(h.args, false);
                try e.f("), vt_{s}, 1 }}; srs_cap* {s} = &{s}_v; ", .{ h.handler, c, c });
                const l: Local = .{ .name = h.name, .c = c, .proto = pn };
                try e.locals.append(e.a, l);
                try caps.append(e.a, l);
            },
        };
        try e.w("__auto_type res_ = ");
        if (last) |x| try e.expr(x) else try e.w("(int64_t)0");
        try e.w("; ");
        var i = caps.items.len;
        while (i > 0) {
            i -= 1;
            const l = caps.items[i];
            const pr = e.protos.get(l.proto.?) orelse return e.fail("unknown protocol", l.proto.?);
            if (pr.drop) |dn| {
                const k = opIndex(pr, dn) orelse return e.fail("unknown drop op", dn);
                try e.f("if ({s}->live) ((int64_t(*)(void*))({s}->vt[{d}]))({s}->self); ", .{ l.c, l.c, k, l.c });
            }
        }
        try e.w("res_; })");
        e.locals.items.len = mark;
    }
};

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn contains(xs: []const []const u8, x: []const u8) bool {
    for (xs) |y| if (eq(x, y)) return true;
    return false;
}

fn unescapedLen(s: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\') i += 1;
        n += 1;
    }
    return n;
}

const prelude =
    \\#include <stdint.h>
    \\#include <stdbool.h>
    \\typedef struct { const uint8_t* p; int64_t n; } srs_str;
    \\typedef struct { void* self; void* const* vt; int64_t live; } srs_cap;
    \\void rt_init(int argc, char** argv);
    \\
;
