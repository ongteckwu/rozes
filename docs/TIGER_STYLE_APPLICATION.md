# Tiger Style Application Guide for Zig Development

**Purpose**: Practical examples of principles to development in Zig.

**Audience**: You (building the parser)

**Key Insight**: Tiger Style isn't just rules—it's a mindset that makes code safer, faster, and more maintainable.

---

## Quick Reference Card

Print this and keep it visible while coding:

```
TIGER STYLE PARSER CHECKLIST:

✅ Safety
   □ 2+ assertions per function (minimum)
   □ Assert pre-conditions (inputs)
   □ Assert post-conditions (outputs)
   □ Assert invariants (middle of function)
   □ Pair assertions (before write AND after read)
   □ Bounded loops (MAX constant)
   □ Explicit types (u32, not usize)
   □ Error handling (try or catch, never ignore)

✅ Performance
   □ Static allocation (ArenaAllocator)
   □ Back-of-envelope sketch done
   □ Comptime where possible
   □ Batching (don't process one-by-one)

✅ Developer Experience
   □ Function ≤ 70 lines
   □ Descriptive names (snake_case, no abbrev)
   □ Comments explain WHY
   □ 100-column line limit

✅ Zero Dependencies
   □ Only Zig stdlib
```

---

## 1. Safety First

### Rule: 2+ Assertions Per Function

**Why**: Catch bugs early, document assumptions, enable fuzzing

**Example: Lexer**

```zig
// ❌ BAD: No assertions
fn scanIdentifier(self: *Lexer) Token {
    const start = self.pos;

    while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
        self.pos += 1;
    }

    return Token{
        .kind = .identifier,
        .start = start,
        .end = self.pos,
        .flags = .{},
    };
}

// ✅ GOOD: Multiple assertions
fn scanIdentifier(self: *Lexer) Token {
    // Assertion 1: Pre-condition - we're at a valid identifier start
    std.debug.assert(self.pos < self.source.len);
    std.debug.assert(isIdentStart(self.source[self.pos]));

    const start = self.pos;

    // Assertion 2: Invariant - position never exceeds length
    while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
        self.pos += 1;
        std.debug.assert(self.pos <= self.source.len); // Loop invariant
    }

    // Assertion 3: Post-condition - we made progress
    std.debug.assert(self.pos > start);

    // Assertion 4: Result is non-empty
    const length = self.pos - start;
    std.debug.assert(length > 0);

    return Token{
        .kind = .identifier,
        .start = start,
        .end = self.pos,
        .flags = .{},
    };
}
```

**Counting Assertions**: This function has **4 assertions** (exceeds minimum of 2) ✅

### Rule: Pair Assertions

**Why**: Catch bugs at the boundary where data becomes invalid

**Example: Token Buffer**

```zig
fn addToken(self: *Lexer, token: Token) !void {
    // BEFORE write: Assert token is valid
    std.debug.assert(token.start <= token.end);
    std.debug.assert(token.end <= self.source.len);
    std.debug.assert(token.kind != .error_token or self.had_error);

    try self.tokens.append(token);

    // AFTER write: Assert it was stored correctly
    const stored = self.tokens.items[self.tokens.items.len - 1];
    std.debug.assert(stored.start == token.start);
    std.debug.assert(stored.kind == token.kind);
}

// Later, when reading:
fn getToken(self: *Parser, index: u32) Token {
    // BEFORE read: Assert index is valid
    std.debug.assert(index < self.tokens.len);

    const token = self.tokens[index];

    // AFTER read: Assert token is valid
    std.debug.assert(token.start <= token.end);
    std.debug.assert(token.end <= self.source.len);

    return token;
}
```

### Rule: Bounded Loops

**Why**: Prevent infinite loops, enable fuzzing, predictable performance

```zig
// ❌ BAD: Unbounded
fn tokenize(self: *Lexer) ![]Token {
    while (true) {
        const token = try self.nextToken();
        try self.tokens.append(token);
        if (token.kind == .eof) break;
    }
    return self.tokens.toOwnedSlice();
}

// ✅ GOOD: Explicit bound
fn tokenize(self: *Lexer) ![]Token {
    const MAX_TOKENS: u32 = 50_000_000;

    var count: u32 = 0;
    while (count < MAX_TOKENS) : (count += 1) {
        const token = try self.nextToken();
        try self.tokens.append(token);
        if (token.kind == .eof) break;
    }

    // Pair assertion: Verify we terminated correctly
    std.debug.assert(count < MAX_TOKENS or self.isEOF());

    return self.tokens.toOwnedSlice();
}
```

### Rule: Explicit Types (u32, not usize)

**Why**: Consistent across platforms, smaller memory, explicit limits

```zig
// ❌ BAD: Architecture-dependent
pub const Span = struct {
    start: usize,  // 8 bytes on 64-bit, 4 on 32-bit
    end: usize,
};

// ✅ GOOD: Explicit size
pub const Span = struct {
    start: u32,  // Always 4 bytes
    end: u32,

    comptime {
        // Assert at compile time
        std.debug.assert(@sizeOf(Span) == 8);
    }
};

// Benefits:
// - Files > 4GB are extremely rare
// - Smaller structs = better cache locality
// - Explicit about limits
```

**Real Impact:**

- 10,000 spans: 80KB (u32) vs 160KB (u64) = 2× memory savings!
- Better cache utilization = faster parsing

### Rule: Error Handling - Never Ignore

```zig
// ❌ BAD: Ignoring error
const num = parseInt(str) catch 0;

// ❌ BAD: Silent failure
_ = parseInt(str);

// ✅ GOOD: Explicit handling
const num = parseInt(str) catch |err| {
    std.debug.print("Parse error: {}\n", .{err});
    return error.InvalidNumber;
};

// ✅ GOOD: Propagate
const num = try parseInt(str);

// ✅ GOOD: Document why we can ignore
const num = parseInt(str) catch unreachable; // str validated at line X
```

---

## 2. Performance

### Rule: Static Allocation at Startup

**Why**: Predictable performance, no allocation spikes, easier to reason about

```zig
// ✅ GOOD: Arena pattern for parser
pub fn parse(allocator: Allocator, source: []const u8) !ParseResult {
    // Create arena - all allocations happen here
    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }

    // All subsequent allocations use the arena
    const arena_alloc = arena.allocator();

    var lexer = Lexer.init(source, .{});
    const tokens = try lexer.tokenize(arena_alloc); // Allocated in arena

    var parser = Parser.init(arena_alloc, source, tokens);
    const file = try parser.parseFile(); // All AST nodes in arena

    // Return arena to caller (they free everything at once)
    return ParseResult{
        .file = file,
        .arena = arena,
    };
}
```

**Memory Profile:**

```
Time →
│
│ Parse Start     Peak Usage        Parse End
│     │          ╱‾‾‾‾‾‾╲              │
│     │         ╱        ╲             │
│     │        ╱          ╲            │
│     │       ╱            ╲           │
│     └──────┘              └──────────┘
│
└─────────────────────────────────────────> Memory

Arena: Single allocation peak, single free
Heap:  Multiple allocs/frees (fragmentation, overhead)
```

### Rule: Back-of-Envelope Sketches

**Before** writing code, estimate performance:

**Example: Lexer Throughput**

```
Target: 300 MB/s

Typical file: 100 KB
Target time: 100 KB / 300 MB/s ≈ 0.33 ms

Assumptions:
- 100 KB ≈ 3000 tokens
- Time per token: 0.33 ms / 3000 ≈ 110 ns
- CPU: 3 GHz → 110 ns = 330 cycles/token

Budget:
- Scan char: ~10 cycles
- Classify token: ~20 cycles
- Append to array: ~30 cycles
- Overhead: ~50 cycles
Total: ~110 cycles ✅ (matches target!)

Conclusion: Approach is feasible if we keep scanning tight
```

### Rule: Comptime Code Generation

**Why**: Move work to compile time, zero runtime cost

```zig
// Operator precedence table (computed once)
pub const BinOp = enum {
    Add, Sub, Mul, Div, Exp,

    pub fn precedence(self: BinOp) u8 {
        return comptime switch (self) {
            .Exp => 17,
            .Mul, .Div => 15,
            .Add, .Sub => 13,
        };
    }
};

// Keyword lookup (perfect hash at comptime)
const KeywordMap = comptime blk: {
    var map: [30]struct { str: []const u8, kind: TokenKind } = undefined;
    map[0] = .{ .str = "const", .kind = .@"const" };
    map[1] = .{ .str = "let", .kind = .@"let" };
    // ... all keywords
    break :blk map;
};

fn lookupKeyword(str: []const u8) ?TokenKind {
    inline for (KeywordMap) |kw| {
        if (std.mem.eql(u8, str, kw.str)) return kw.kind;
    }
    return null;
}

// Comptime assertions (verify design)
comptime {
    std.debug.assert(BinOp.Mul.precedence() > BinOp.Add.precedence());
    std.debug.assert(@sizeOf(Token) <= 16); // Keep tokens small
}
```

### Rule: Batching

**Why**: Amortize costs, reduce context switches

```zig
// ❌ BAD: Process tokens one-by-one
fn parseExpressions(self: *Parser) ![]Expr {
    var exprs = ArrayList(Expr).init(self.allocator);

    while (...) {
        const expr = try self.parseExpr();  // Allocates individually
        try exprs.append(expr);
    }

    return exprs.toOwnedSlice();
}

// ✅ GOOD: Batch allocations
fn parseExpressions(self: *Parser) ![]Expr {
    // Pre-allocate based on estimate
    const estimated_count = estimateExprCount(self.tokens);
    var exprs = try ArrayList(Expr).initCapacity(self.allocator, estimated_count);

    while (...) {
        const expr = try self.parseExpr();
        exprs.appendAssumeCapacity(expr);  // No allocation!
    }

    return exprs.toOwnedSlice();
}
```

---

## 3. Developer Experience

### Rule: 70-Line Function Limit

**Why**: Easier to understand, test, maintain

**Strategy: Split by Responsibility**

```zig
// ❌ BAD: 150-line function doing everything
fn parseForStatement(self: *Parser) !u32 {
    // ... 150 lines of:
    // - Parsing init
    // - Parsing condition
    // - Parsing update
    // - Parsing body
    // - Error recovery
    // - Validation
}

// ✅ GOOD: Split into focused helpers
fn parseForStatement(self: *Parser) !u32 {
    // Only control flow here (18 lines)
    self.expect(.@"for");
    self.expect(.l_paren);

    const init = try self.parseForInit();
    self.expect(.semicolon);

    const cond = try self.parseForCondition();
    self.expect(.semicolon);

    const update = try self.parseForUpdate();
    self.expect(.r_paren);

    const body = try self.parseStatement();

    return try self.addNode(.{
        .kind = .for_stmt,
        .main_token = for_token,
        .data = .{ .lhs = init, .rhs = try self.addExtra(&.{ cond, update, body }) },
    });
}

// Pure logic, no control flow (22 lines)
fn parseForInit(self: *Parser) !u32 {
    if (self.match(.@"var") or self.match(.@"let") or self.match(.@"const")) {
        return try self.parseVarDecl();
    }
    if (self.match(.semicolon)) {
        return 0; // Empty init
    }
    return try self.parseExpr(0);
}

// Pure logic, no control flow (15 lines)
fn parseForCondition(self: *Parser) !u32 {
    if (self.check(.semicolon)) {
        return 0; // Empty condition (infinite loop)
    }
    return try self.parseExpr(0);
}

// Pure logic, no control flow (12 lines)
fn parseForUpdate(self: *Parser) !u32 {
    if (self.check(.r_paren)) {
        return 0; // Empty update
    }
    return try self.parseExpr(0);
}
```

**Line Count**: 18 + 22 + 15 + 12 = 67 lines total, split into 4 functions ✅

### Rule: Descriptive Names (No Abbreviations)

```zig
// ❌ BAD: Cryptic abbreviations
fn parseVD(p: *P) !u32 {
    const k = p.cur().k;
    // ...
}

// ✅ GOOD: Clear, descriptive
fn parseVariableDeclaration(self: *Parser) !u32 {
    const kind = self.current().kind;
    // ...
}

// Units in variable names (big-endian naming)
const latency_ms_max: u32 = 1000;    // ✅ Groups with latency_ms_min
const max_latency_ms: u32 = 1000;    // ❌ Doesn't group nicely

// Matching lengths for symmetry
const source_offset: u32 = 0;  // ✅ Aligns with:
const target_offset: u32 = 10; // ✅ target (same length as source)

const src_offset: u32 = 0;  // ❌ Doesn't align:
const dest_offset: u32 = 10; // ❌ dest (different length)
```

### Rule: Comments Explain WHY

```zig
// ❌ BAD: Comments repeat code
// Advance position by 1
self.pos += 1;

// ❌ BAD: Obvious comment
// Parse expression
const expr = try self.parseExpr();

// ✅ GOOD: Explain the reasoning
// Skip BOM (U+FEFF) if present at start of file.
// Some editors add this, and JS parsers silently ignore it.
if (self.pos == 0 and self.source.len >= 3) {
    if (std.mem.eql(u8, self.source[0..3], "\xEF\xBB\xBF")) {
        self.pos = 3;
    }
}

// ✅ GOOD: Document surprising behavior
// ASI rule: 'return' on its own line implicitly inserts semicolon.
// This is why "return\n expr" doesn't work in JavaScript.
if (self.has_line_terminator_before_next()) {
    return try self.addNode(.{ .kind = .return_stmt, .data = .{ .lhs = 0, .rhs = 0 } });
}
```

### Rule: 100-Column Line Limit

```zig
// ❌ BAD: Exceeds 100 columns
const node = try self.addNode(.{ .kind = .binary_expr, .main_token = op_token, .data = .{ .lhs = left_node, .rhs = right_node } });

// ✅ GOOD: Use trailing comma, let zig fmt handle it
const node = try self.addNode(.{
    .kind = .binary_expr,
    .main_token = op_token,
    .data = .{
        .lhs = left_node,
        .rhs = right_node,
    },
});
```

---

## 4. Real-World Examples

### Complete Function (Tiger Style)

```zig
/// Parse binary expression using Pratt parsing.
/// Min binding power determines which operators to consume.
fn parseBinaryExpr(self: *Parser, min_bp: u8) !u32 {
    // Assertion 1: Pre-condition - recursion bounded
    std.debug.assert(self.recursion_depth < MAX_RECURSION);

    // Assertion 2: Pre-condition - not at EOF
    std.debug.assert(!self.isEOF());

    self.recursion_depth += 1;
    defer self.recursion_depth -= 1;

    // Parse left-hand side
    var lhs = try self.parsePrefixExpr();

    // Assertion 3: Post-condition from prefix parse
    std.debug.assert(lhs != 0); // Valid node index

    // Parse operators in loop (bounded by token count)
    while (!self.isEOF()) {
        const op = self.current().kind.toBinaryOp() orelse break;
        const bp = op.bindingPower();

        // Operator not strong enough, stop
        if (bp < min_bp) break;

        const op_token = self.pos;
        self.advance();

        // Parse right-hand side with higher precedence
        const rhs = try self.parseBinaryExpr(bp + 1);

        // Assertion 4: Post-condition from rhs parse
        std.debug.assert(rhs != 0);

        // Create binary node
        lhs = try self.addNode(.{
            .kind = .binary_expr,
            .main_token = op_token,
            .data = .{ .lhs = lhs, .rhs = rhs },
        });

        // Assertion 5: Node was added successfully
        std.debug.assert(lhs < self.nodes.len);
    }

    // Assertion 6: Final post-condition
    std.debug.assert(lhs != 0);
    std.debug.assert(lhs < self.nodes.len);

    return lhs;
}

// Line count: 47 lines (under 70 ✅)
// Assertion count: 6 (exceeds minimum of 2 ✅)
```

### Error Recovery Pattern

```zig
fn parseStatement(self: *Parser) !u32 {
    const start_pos = self.pos;

    const node = self.parseStatementInner() catch |err| {
        // Log error for diagnostics
        try self.diagnostics.append(.{
            .severity = .Error,
            .span = self.current_span(),
            .message = "Failed to parse statement",
            .code = "E2001",
        });

        // Tiger Style: Bound error recovery
        self.syncToStatementBoundary();

        // Pair assertion: We made some progress (or reached EOF)
        std.debug.assert(self.pos > start_pos or self.isEOF());

        // Return error node (partial AST)
        return try self.addNode(.{
            .kind = .error_node,
            .main_token = start_pos,
            .data = .{ .lhs = 0, .rhs = 0 },
        });
    };

    // Pair assertion: Valid node returned
    std.debug.assert(node < self.nodes.len);

    return node;
}

fn syncToStatementBoundary(self: *Parser) void {
    const MAX_SKIP: u32 = 10_000; // Tiger Style: explicit bound
    var skipped: u32 = 0;

    while (skipped < MAX_SKIP and !self.isEOF()) : (skipped += 1) {
        switch (self.current().kind) {
            .semicolon, .r_brace => {
                self.advance(); // Consume delimiter
                break;
            },
            .@"const", .@"let", .@"var", .@"function", .@"class" => {
                // Start of new statement
                break;
            },
            else => self.advance(),
        }
    }

    // Pair assertion
    std.debug.assert(skipped < MAX_SKIP or self.isEOF());
}
```

---

## 5. Common Mistakes & Fixes

### Mistake 1: Forgetting Assertions

```zig
// ❌ Before (0 assertions)
fn addToken(self: *Lexer, token: Token) !void {
    try self.tokens.append(token);
}

// ✅ After (3 assertions)
fn addToken(self: *Lexer, token: Token) !void {
    std.debug.assert(token.start <= token.end);
    std.debug.assert(self.tokens.items.len < MAX_TOKENS);

    try self.tokens.append(token);

    std.debug.assert(self.tokens.items.len > 0);
}
```

### Mistake 2: Unbounded Loops

```zig
// ❌ Before
while (self.current() != '}') {
    try self.parseObjectProperty();
}

// ✅ After
const MAX_PROPS: u32 = 100_000;
var count: u32 = 0;
while (count < MAX_PROPS and self.current() != '}') : (count += 1) {
    try self.parseObjectProperty();
}
std.debug.assert(count < MAX_PROPS or self.current() == '}');
```

### Mistake 3: Using usize

```zig
// ❌ Before
pub const Token = struct {
    start: usize,  // 8 bytes on 64-bit
    end: usize,
};

// ✅ After
pub const Token = struct {
    start: u32,  // Always 4 bytes
    end: u32,

    comptime {
        std.debug.assert(@sizeOf(Token) <= 16);
    }
};
```

---

## 6. Testing Tiger Style Compliance

### Automated Checks

```zig
// scripts/check_tiger_style.zig

pub fn main() !void {
    const source_file = try std.fs.cwd().readFileAlloc(...);

    var violations = ArrayList(Violation).init(...);

    try checkFunctionLength(source_file, &violations);
    try checkAssertionDensity(source_file, &violations);
    try checkBoundedLoops(source_file, &violations);
    try checkExplicitTypes(source_file, &violations);

    if (violations.items.len > 0) {
        std.debug.print("Tiger Style violations found:\n", .{});
        for (violations.items) |v| {
            std.debug.print("  {s}:{}: {s}\n", .{ v.file, v.line, v.message });
        }
        std.process.exit(1);
    }

    std.debug.print("✅ All Tiger Style checks passed!\n", .{});
}
```

Run: `zig build tiger-check`

---

## Summary: Tiger Style Mindset

**Not just rules, but a way of thinking:**

1. **Paranoid Safety** - Assume nothing, verify everything
2. **Predictable Performance** - Know exactly what your code does
3. **Readable Code** - Your future self will thank you
4. **Zero Technical Debt** - Do it right the first time

**The Result:**

- Fewer bugs (caught early by assertions)
- Faster code (optimized upfront)
- Easier maintenance (clear, bounded functions)
- Proud craftsmanship (code you can be proud of)

---

**Next**: Start implementing! → [PARSER_IMPLEMENTATION_GUIDE.md](./PARSER_IMPLEMENTATION_GUIDE.md)
