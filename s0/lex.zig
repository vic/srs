//! srs lexer: tokens + Scala3 optional-brace layout (nl / indent / dedent).
const std = @import("std");

pub const Tag = enum { ident, int, str, char, op, nl, indent, dedent, eof };

pub const Tok = struct {
    tag: Tag,
    text: []const u8,
    line: u32,
};

pub const Error = error{ Lex, OutOfMemory };

pub const Lexer = struct {
    src: []const u8,
    toks: std.ArrayList(Tok) = .empty,
    err_line: u32 = 0,
    err_msg: []const u8 = "",

    fn fail(self: *Lexer, line: u32, msg: []const u8) Error {
        self.err_line = line;
        self.err_msg = msg;
        return error.Lex;
    }

    fn push(self: *Lexer, gpa: std.mem.Allocator, tag: Tag, text: []const u8, line: u32) Error!void {
        try self.toks.append(gpa, .{ .tag = tag, .text = text, .line = line });
    }

    pub fn run(self: *Lexer, gpa: std.mem.Allocator) Error![]Tok {
        const s = self.src;
        var indents: std.ArrayList(u32) = .empty;
        try indents.append(gpa, 0);
        var i: usize = 0;
        var line: u32 = 1;
        var depth: u32 = 0; // open ( and [: layout off inside
        var at_bol = true;
        while (i < s.len) {
            if (at_bol and depth == 0) {
                var col: u32 = 0;
                var j = i;
                while (j < s.len and s[j] == ' ') : (j += 1) col += 1;
                if (j < s.len and s[j] == '\t') return self.fail(line, "tab in indentation");
                const blank = j >= s.len or s[j] == '\n' or (s[j] == '/' and j + 1 < s.len and s[j + 1] == '/');
                i = j;
                at_bol = false;
                if (!blank) {
                    const top = indents.items[indents.items.len - 1];
                    if (col > top) {
                        try indents.append(gpa, col);
                        try self.push(gpa, .indent, "", line);
                    } else {
                        while (col < indents.items[indents.items.len - 1]) {
                            _ = indents.pop();
                            try self.push(gpa, .dedent, "", line);
                        }
                        if (col != indents.items[indents.items.len - 1]) return self.fail(line, "bad dedent");
                    }
                }
                continue;
            }
            const c = s[i];
            if (c == '\n') {
                if (depth == 0 and self.toks.items.len > 0 and self.toks.items[self.toks.items.len - 1].tag != .nl and
                    self.toks.items[self.toks.items.len - 1].tag != .indent and self.toks.items[self.toks.items.len - 1].tag != .dedent)
                    try self.push(gpa, .nl, "", line);
                line += 1;
                i += 1;
                at_bol = true;
            } else if (c == ' ' or c == '\r') {
                i += 1;
            } else if (c == '/' and i + 1 < s.len and s[i + 1] == '/') {
                while (i < s.len and s[i] != '\n') i += 1;
            } else if (std.ascii.isAlphabetic(c) or c == '_') {
                const b = i;
                while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '_')) i += 1;
                try self.push(gpa, .ident, s[b..i], line);
            } else if (std.ascii.isDigit(c)) {
                const b = i;
                while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
                try self.push(gpa, .int, s[b..i], line);
            } else if (c == '"' or c == '\'') {
                const b = i + 1;
                i += 1;
                while (i < s.len and s[i] != c and s[i] != '\n') : (i += 1) {
                    if (s[i] == '\\') i += 1;
                }
                if (i >= s.len or s[i] != c) return self.fail(line, "unterminated literal");
                try self.push(gpa, if (c == '"') .str else .char, s[b..i], line);
                i += 1;
            } else {
                const two = [_][]const u8{ "=>", "==", "!=", "<=", ">=", "&&", "||", "~>" };
                var len: usize = 1;
                for (two) |t| {
                    if (std.mem.startsWith(u8, s[i..], t)) len = 2;
                }
                if (len == 1 and std.mem.indexOfScalar(u8, "()[]{},:=+-*/%<>!.^@", c) == null)
                    return self.fail(line, "bad character");
                if (c == '(' or c == '[') depth += 1;
                if ((c == ')' or c == ']') and depth > 0) depth -= 1;
                try self.push(gpa, .op, s[i .. i + len], line);
                i += len;
            }
        }
        if (self.toks.items.len > 0 and self.toks.items[self.toks.items.len - 1].tag != .nl and
            self.toks.items[self.toks.items.len - 1].tag != .dedent)
            try self.push(gpa, .nl, "", line);
        while (indents.items.len > 1) {
            _ = indents.pop();
            try self.push(gpa, .dedent, "", line);
        }
        try self.push(gpa, .eof, "", line);
        return self.toks.items;
    }
};

fn tags(gpa: std.mem.Allocator, src: []const u8) ![]const Tag {
    var lx: Lexer = .{ .src = src };
    const ts = try lx.run(gpa);
    var out: std.ArrayList(Tag) = .empty;
    for (ts) |t| try out.append(gpa, t.tag);
    return out.items;
}

test "layout: indent block then dedent" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const got = try tags(a.allocator(), "a\n  b\nc\n");
    try std.testing.expectEqualSlices(Tag, &.{ .ident, .nl, .indent, .ident, .nl, .dedent, .ident, .nl, .eof }, got);
}

test "layout: parens suppress newlines, comments and blanks skipped" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    const got = try tags(a.allocator(), "f(a,\n  b) // c\n\n  // x\ng\n");
    try std.testing.expectEqualSlices(Tag, &.{ .ident, .op, .ident, .op, .ident, .op, .nl, .ident, .nl, .eof }, got);
}

test "layout: bad dedent rejected (mutant)" {
    var a = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer a.deinit();
    try std.testing.expectError(error.Lex, tags(a.allocator(), "a\n    b\n  c\n"));
}
