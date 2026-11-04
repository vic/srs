//! srs-core AST.
pub const Type = struct {
    name: []const u8,
    /// protocol state `P[s]` / `P[s ~> t]`.
    st_from: ?[]const u8 = null,
    st_to: ?[]const u8 = null,
    /// capture set `T^{r}`; null = unannotated.
    caps: ?[]const []const u8 = null,
};

pub const Param = struct { name: []const u8, ty: Type };

pub const Arm = struct {
    /// null = wildcard `_`.
    ctor: ?[]const u8,
    binds: []const []const u8,
    body: *Expr,
};

pub const Stmt = union(enum) {
    val: struct { name: []const u8, ty: ?Type, e: *Expr, mutable: bool },
    handle: struct { name: []const u8, handler: []const u8, args: []*Expr },
    expr: *Expr,
};

pub const Expr = union(enum) {
    int: i64,
    boolean: bool,
    /// raw text between quotes, escapes kept.
    str: []const u8,
    unit,
    name: []const u8,
    call: struct { callee: []const u8, args: []*Expr },
    method: struct { recv: []const u8, op: []const u8, args: []*Expr },
    bin: struct { op: []const u8, l: *Expr, r: *Expr },
    un: struct { op: []const u8, e: *Expr },
    if_: struct { c: *Expr, t: *Expr, e: *Expr },
    match: struct { scrut: *Expr, arms: []Arm },
    block: struct { stmts: []Stmt, last: ?*Expr },
    while_: struct { c: *Expr, body: *Expr },
    assign: struct { name: []const u8, e: *Expr },
};

pub const Fn = struct {
    name: []const u8,
    params: []Param,
    ret: Type,
    body: ?*Expr,
    line: u32,
};

pub const Case = struct { name: []const u8, fields: []const Param };

pub const Trans = struct { from: []const u8, to: []const u8 };

pub const Op = struct { name: []const u8, params: []Param, ret: Type, trans: []Trans };

pub const Proto = struct {
    name: []const u8,
    states: []const []const u8,
    start: []const u8,
    ends: []const []const u8,
    ops: []Op,
    drop: ?[]const u8,
};

pub const Decl = union(enum) {
    ext: Fn,
    def: Fn,
    enum_: struct { name: []const u8, cases: []Case },
    proto: Proto,
    handler: struct { name: []const u8, proto: []const u8, fns: []Fn },
};
