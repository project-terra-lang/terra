# Terra Language Reference v0

This document describes the implemented Terra v0 surface syntax. Terra is a
small research language that transpiles to Erlang source and runs on the BEAM
VM. The language should stay simple and grow incrementally.

## Program Shape

A Terra source file may begin with one optional `temp region(capacity);`
configuration, followed by module-scope `global` and `const` declarations and
function declarations. Other `local`, `temp`, and ordinary statements are only
valid inside a function or block scope. Every valid program must declare exactly
one entry point:

```terra
function Number Main(String Args) {
  return 0;
}
```

The entry point receives command-line arguments as `String Args` and returns a
`Number`.

The current compiler pipeline is split into explicit passes:

```text
parsing -> name_resolution -> type_checking -> unreachable_code -> definite_return -> warning_analysis -> lowering -> codegen
```

`program:parse_file/1` runs the frontend passes and records them in the
program AST. `transpiler:codegen_pass/1` turns that lowered AST into Erlang
source.

File parsing preserves each function's Terra source path and declaration line.
Code generation emits Erlang `-file` metadata for the exported entry wrapper,
ordinary functions, and tail-step helpers, then resets runtime-only helpers to
a synthetic file. BEAM stack traces therefore retain Terra frames, and
`terra run` uses the mapped function boundary to render the nearest executable
Terra source line when a runtime failure occurs.

Compiler output is deterministic for the same source and path. Code generation
preserves source declaration order, warning analysis finalizes bindings in
declaration order, and BEAM compilation uses Erlang's deterministic mode.

## Lexical Rules

Whitespace separates tokens and has no meaning outside strings and character
literals. Line comments start with `--` or `//` and continue to the end of the
line.

Identifiers begin with a letter or underscore and may contain letters, digits,
and underscores. Keywords are reserved.

String literals use double quotes and support `\n`, `\t`, `\r`, `\"`, and `\\`
escapes. Character literals use single quotes around one character and evaluate
as Erlang-compatible integer character values.

## Types

The current built-in types are:

```text
Number Int SInt Float Atom Bool Map RestrictedMap List Tuple String State Var
```

Any built-in or user-defined type may be wrapped in a temporary-region pointer
type by prefixing it with `*`, such as `*String` or `*Player`.

`Number` accepts `Int`, `SInt`, and `Float` values. `Var` asks the compiler to
infer the concrete type from the initializer. `State` is currently accepted as a
research placeholder type for future runtime state semantics.

### Numeric Semantics

`Int` and `SInt` both use BEAM arbitrary-precision integers. `SInt` marks
explicitly signed source values, including negative literals, but neither type
is a statically checked numeric range. Integer arithmetic therefore does not
wrap or overflow. `Float` uses the BEAM floating-point representation; its
precision and exceptional arithmetic behavior follow the Erlang runtime.
Because `SInt` is not a narrower runtime range, ordinary `Int` values may be
used where `SInt` is expected.

For `+` and `*`, mixed operands promote in this order: `Float`, `SInt`, `Int`.
Same-type integer arithmetic preserves its type; mixed subtraction follows the
same promotion order. A statically broad `Number` operand produces `Number`.
The `/` operator accepts any numeric pair and always produces `Float`.
Division by a compile-time zero is rejected during constant evaluation;
division by a runtime zero raises the ordinary BEAM arithmetic error.

Numeric constructors perform explicit conversions and require exactly one
numeric argument:

```terra
Float(3)    // 3.0
SInt(3.9)   // 3, truncating toward zero
Int(3.9)    // 3, truncating toward zero
Number(3)   // preserves the runtime numeric value
```

`Int` and `SInt` both truncate floating-point inputs toward zero; they differ in
their source-level type, not their BEAM representation. Numeric constructors do
not parse strings or convert booleans. Mixed `Int`, `SInt`, and `Float` comparisons compare their
numeric values and produce `Bool`; string ordering remains string-only.

`null` and `nil` are tokenized but rejected as variable values.

### User-Defined Structs

Structs define small immutable data values at module scope:

```terra
struct Player {
  String name;
  Int score;
}

function Int Score(Player player) {
  return player.score;
}
```

Construction is positional and follows declaration order: `Player("Ada", 7)`.
The compiler checks constructor arity and argument types, validates field names,
and preserves field types through chained member access. Struct types may be
used for fields, variables, parameters, and function returns. At runtime a
struct is an immutable tagged BEAM map; its representation is an implementation
detail rather than additional mutation syntax.

### Tagged Enums

Enums provide immutable tagged alternatives with optional typed payloads:

```terra
enum Result {
  variant Ok(Int value);
  variant Error(String message);
  variant Pending;
}

local Result result = Result.Ok(7);
```

The `variant` keyword explicitly declares a data constructor. A declaration such
as `variant Ok(Int value);` defines the tag `:Ok`, the payload field `value`, and
the constructor signature `Result.Ok(Int) -> Result`; no undeclared constructor
is synthesized. Constructors only package immutable data. Programs that need
validation or behavior around construction can define an ordinary function that
returns the enum. Constructor calls use `Enum.Variant(...)` and always include
parentheses, including variants without payload fields. Constructor arity and
payload types are checked.
Every value exposes an `Atom` through `.tag`, such as `:Ok`, and payloads are
available by their declared field names. Code should check `.tag` before reading
a variant-specific payload; accessing a field absent from the runtime variant
raises a missing-map-key error. Enum types may be used for fields, variables,
parameters, and function returns. Values lower to immutable tagged BEAM maps.

### Temporary-Region Pointers

Pointers provide explicit fake mutability without making ordinary Terra
bindings reassignable:

```terra
local *String name = "initial";
name.* = "Terra";
stdout(name.*);
```

A pointer declaration allocates one slot containing its initializer. Prefix
`*` copies an existing value into a new pointer slot:

```terra
local String source = "Ada";
local *String copied = *source;
```

The postfix `.*` helper reads a slot, and `pointer.* = value;` writes a
type-compatible value into it. Pointer types are valid in plain local variables,
function parameters and returns, call arguments, struct fields, and enum
payloads. Pointer allocation is rejected for `const`, `global`, and `temp`
storage. It is also kept separate from lazy, computed, atomic, and thread-local
storage so every pointer has one predictable region lifetime.

The optional first declaration `temp region(N);` sets a fixed capacity of `N`
pointer slots. Exceeding it raises `terra_temporary_region_full`. Without the
declaration, the compiler records the number of pointer-producing expressions
as an initial estimate and the runtime region may grow for repeated function or
recursive execution.

The generated `main/1` wrapper creates the process-local region before calling
Terra `Main` and removes it in an `after` block on both success and failure.
Pointer handles contain their owner process, region reference, and slot. Access
after cleanup raises `terra_dangling_pointer`; access from another process raises
`terra_cross_process_pointer`. Terra never exposes a raw machine address.

## Functions

Functions use the `function` keyword, a return type, a name, typed parameters,
and a brace-delimited body.

```terra
function Int Double(Int value) {
  return value * 2;
}
```

Multiple return values are declared with parenthesized return types and compile
as Erlang tuples.

```terra
function (String, Number) Analyze(Int value) {
  return "score", value;
}
```

Function bodies may call other functions declared in the same file. Calls are
type checked against the callee parameters and return values.

A user-function call returned directly with `return Function(args);` is a tail
call. The backend lowers these returns through a generated dispatch loop whose
function call is in BEAM tail position, including self-recursive and mutually
recursive calls. Calls followed by more work remain ordinary calls.

Every function must declare a concrete return type. Terra has no `Void` or
`void` return type, and `return;` is not valid; a return statement must return
one or more values matching the declared type list.

```terra
Analyze(10);
```

Writing a zero-argument function name followed only by `;` makes a once-only
invocation:

```terra
Initialize;
```

The once-only state is scoped to the generated module, target function, and
current BEAM process. The first successful `Initialize;` executes the function
and caches its return value; later `Initialize;` statements in that process
reuse the cached value without executing the body. A normal `Initialize()` call
always executes and neither reads nor writes the once-only cache. A different
BEAM process has an independent cache.

Failures are not cached, so a later once-only invocation may retry. Reentering
the same once-only function before its first invocation finishes raises a
`terra_once_reentrant` runtime error. The cache has process lifetime and is
discarded when that BEAM process exits.

## Variables

Variable declarations are immutable. Direct reassignment is rejected.

```terra
const Int max_players = 128;
global State state = State();
local Int count = 10;
temp String label = "debug";
```

At module scope, only `global` and `const` declarations are valid. Module
`const` declarations are compile-time constants and are resolved before module
globals and ordinary function bindings. Module `global` declarations may refer
to module constants and earlier module bindings, but not to function parameters
or local variables.

Inside function bodies, supported declaration scopes are `global`, `local`, and
`temp`. Supported declaration modifiers are:

```text
lazy const computed atomic thread_local
```

Examples:

```terra
local lazy Number delayed = Work();
local const Int base = 2 + 3;
local computed Int next = base + 1;
local atomic Int counter = 0;
local thread_local String session = "local";
```

`const` declarations fold simple literal expressions and const references during
parsing. The remaining storage forms have runtime semantics:

- `global` initializes successfully once per generated module and name, then
  shares the immutable value across BEAM processes through `persistent_term`.
  Its initializer must be closed: it cannot reference parameters or lexical
  variables. Concurrent first access is serialized, and failed initialization
  is retryable. Global names must be unique across the module.
- `thread_local` initializes successfully once per declaration site and BEAM process.
  Its process-dictionary value disappears when the process exits, and failed
  initialization is retryable.
- `atomic` accepts only `Int` or `SInt`. It stores the value in a one-cell BEAM
  `atomics` reference and reads through `atomics:get/2`. A `global atomic`
  declaration shares the cell module-wide; local and temporary atomic cells are
  created for each function invocation.
- `computed` creates a local getter and reevaluates its expression on every
  reference. The expression is not evaluated when declared.
- A `temp Type` value has immutable function-local lifetime like `local`. The
  separate module-level `temp region(N);` construct configures pointer capacity.

`global computed`, `global lazy`, and `global thread_local` are rejected because
their storage/lifetime guarantees conflict.

Variable names may be shadowed by later declarations. References resolve to the
newest visible binding in the current parser environment.

Duplicate names inside a single parameter list, multiple-return binding, or
destructuring binding are rejected. Loop bindings may not use `it`, because
loops already provide `it` as an implicit counter.

Function bodies are lexical scopes. Control-flow bodies create child scopes:
variables declared inside `if`, `elseif`, `else`, `unless`, switch cases, and
loop bodies are visible inside that block and disappear after the closing brace.
Loop helper bindings such as `it` and `for_each` item names are also block-local.

## Destructuring And Multiple Binding

Tuple destructuring binds multiple immutable variables:

```terra
local Tuple pair = (1, "one");
local (Int id, String label) = pair;
```

Destructuring a tuple variable marks that source as moved for the variable
parser, and later use of the moved source is rejected.

Multiple return values can be assigned to typed locals:

```terra
local String label, Number value = Analyze(10);
```

## Expressions

Implemented literals:

```terra
123
-5
10.5
"hello"
'T'
true
false
:ready
[1, 2, 3]
(1, "one")
#(:name => "Terra", :version => 1)
```

Bounded maps use a constructor with a non-negative `Int` capacity and an
optional initial `Map`:

```terra
RestrictedMap(4)
RestrictedMap(4, #(:name => "Terra", :version => 1))
```

The initializer must not contain more members than the declared capacity.
Terra maps are immutable, so the capacity bounds construction rather than a
later mutation operation. `value.count` returns an `Int` member count and
`value.members` returns a `List` of key/value tuples for both `Map` and
`RestrictedMap`. Other member names continue to perform ordinary key lookup.

Function and constructor-style calls use parentheses:

```terra
Double(4)
List()
State()
```

`try` may prefix a user-function call in any expression position or as a
standalone call:

```terra
local Int value = try LoadValue();
try Record(value);
return try Forward(value);
```

On success, `try` evaluates to the function's ordinary declared return value.
On failure, it re-raises the original BEAM exception with its reason and stack
unchanged, allowing `terra run` to retain the originating Terra source frame.
Constructors and non-call expressions reject `try`. Bare calls remain valid in
Terra v0 for compatibility; `try` documents and preserves explicit propagation.

The pipe operator passes its left value as the first argument of the user
function on its right. Pipelines associate left-to-right:

```terra
return 2 |> Increment() |> Add(3);
```

This is equivalent to `Add(Increment(2), 3)`. Each stage is type checked using
the inserted first argument. A failure in the left expression or any called
stage propagates its original BEAM class, reason, stack, and Terra source frame.
The right side must be a user-function call; a returned final stage continues
to use Terra's tail-call dispatch.

Member access chains use dots. Map `.count` and `.members` have the concrete
types described above; ordinary key access currently infers to `Var`:

```terra
profile.name
item.it.value
```

Implemented operators, from tighter to looser binding:

```text
! -
* /
+ -
== != < <= > >=
&&
||
```

Arithmetic follows the numeric promotion and division rules above. String `+`
concatenates two strings. Comparisons produce `Bool`; ordering comparisons are
supported for mixed numeric types and for two strings. `&&` and `||` require
`Bool` operands and short-circuit in generated Erlang.

## Statements

Statements usually end with `;`. Brace-delimited control-flow bodies do not use
a trailing semicolon.

### Return

```terra
return value;
return first, second;
```

Return expressions must match the declared function return types.
Every declared function must definitely return on every path. A trailing
fall-through is rejected even though the backend can generate default Erlang
values internally.

Statements after a guaranteed return are rejected as unreachable code.

### Console Output

`stdout(...)` is the built-in console output intrinsic.

```terra
stdout("hello");
stdout(value);
```

### Conditions

Conditions must evaluate to `Bool`.

```terra
if total > 10 {
  stdout("large");
} elseif total == 10 {
  stdout("exact");
} else {
  stdout("small");
}
```

`unless` supports an optional `else` branch:

```terra
unless enabled {
  stdout("disabled");
} else {
  stdout("enabled");
}
```

### Switch

Switch syntax is written as `if subject == { ... }`. Cases break by default and
must include a final default `case:`.

```terra
if status == {
  case :ready:
    stdout("ready");
  case:
    stdout("unknown");
}
```

Case patterns must be type-compatible with the switch subject. The default case
must be last. Duplicate case patterns are rejected.

Enum switches may match a declared variant and destructure its payload:

```terra
if result == {
  case Result.Ok(bind value):
    return value;
  case Result.Error(bind message):
    stdout(message);
    return -1;
  case Result.Pending():
    return 0;
  case:
    return 0;
}
```

Each payload position must use `bind name` or `_`. Bound names receive the
declared payload type, are immutable, and exist only inside that case. `_`
matches without creating a binding. Enum name, variant name, payload arity, and
duplicate bindings are checked statically. Terra v0 intentionally limits
destructuring patterns to enum switch cases; literals and expressions remain
ordinary equality cases.

### Loops

`for_each` iterates over `List`, `Tuple`, `Map`, `RestrictedMap`, and `String`
values. The body
receives the named binding and an implicit `it` counter.

```terra
for_each name in names {
  stdout(it);
  stdout(name);
}
```

`for` currently accepts only `range(limit)` and exposes `it`:

```terra
for range(3) {
  stdout(it);
}
```

`while` and `do_while` conditions must be `Bool` and also expose `it`:

```terra
while it < 2 {
  stdout(it);
}

do_while it < 1 {
  stdout(it)
}
```

## Grammar Sketch

This sketch is intentionally small and tracks the current parser. It is not yet
a formal parser generator grammar.

```ebnf
program         = [ region_decl ], { module_item } ;
region_decl     = "temp", "region", "(", integer, ")", ";" ;
module_item     = struct_decl | enum_decl | module_decl | function_decl ;
module_decl     = global_decl | const_decl ;
struct_decl     = "struct", identifier, "{", { field_decl }, "}" ;
field_decl      = value_type, identifier, ";" ;
enum_decl       = "enum", identifier, "{", { variant_decl }, "}" ;
variant_decl    = "variant", identifier, [ "(", [ params ], ")" ], ";" ;
function_decl   = "function", return_types, identifier, "(", [ params ], ")",
                  block ;
return_types    = value_type | "(", value_type, { ",", value_type }, ")" ;
params          = param, { ",", param } ;
param           = value_type, identifier ;
value_type      = type | "*", type ;
block           = "{", { statement }, "}" ;

statement       = var_decl
                | destructure_decl
                | multi_binding
                | return_stmt
                | call_stmt
                | try_call_stmt
                | once_call_stmt
                | pointer_write
                | if_stmt
                | unless_stmt
                | switch_stmt
                | for_each_stmt
                | for_range_stmt
                | while_stmt
                | do_while_stmt ;

global_decl     = "global", [ "const" | "atomic" ], type, identifier, "=",
                  expr, ";" ;
const_decl      = "const", [ type ], identifier, "=", expr, ";" ;
var_decl        = scope, [ modifier ], value_type, identifier, "=", expr, ";" ;
pointer_write   = identifier, ".", "*", "=", expr, ";" ;
destructure_decl = scope, "(", binding, { ",", binding }, ")", "=", expr, ";" ;
multi_binding   = scope, binding, ",", binding, { ",", binding }, "=", expr, ";" ;
binding         = type, identifier ;
scope           = "global" | "local" | "temp" ;
modifier        = "lazy" | "const" | "computed" | "atomic" | "thread_local" ;

return_stmt     = "return", expr, { ",", expr }, ";" ;
call_stmt       = call, ";" ;
try_call_stmt   = "try", call, ";" ;
once_call_stmt  = identifier, ";" ;

if_stmt         = "if", expr, block, { "elseif", expr, block },
                  [ "else", block ] ;
unless_stmt     = "unless", expr, block, [ "else", block ] ;
switch_stmt     = "if", expr, "==", "{", case_clause, { case_clause },
                  default_case, "}" ;
case_clause     = "case", ( enum_pattern | expr ), ":", { statement } ;
default_case    = "case", ":", { statement } ;
enum_pattern    = identifier, ".", identifier, "(", [ pattern_arg,
                  { ",", pattern_arg } ], ")" ;
pattern_arg     = "bind", identifier | "_" ;

for_each_stmt   = "for_each", identifier, "in", expr, block ;
for_range_stmt  = "for", call_to_range, block ;
while_stmt      = "while", expr, block ;
do_while_stmt   = "do_while", expr, block ;

expr            = pipe ;
pipe            = logical_or, { "|>", call } ;
logical_or      = logical_and, { "||", logical_and } ;
logical_and     = comparison, { "&&", comparison } ;
comparison      = additive, [ comp_op, additive ] ;
additive        = multiplicative, { add_op, multiplicative } ;
multiplicative  = unary, { mul_op, unary } ;
unary           = [ "!" | "-" | "try" | "*" ], unary | primary ;
primary         = literal
                | identifier
                | call
                | variant
                | member
                | list
                | tuple_or_group
                | map
                | restricted_map ;

call            = identifier, "(", [ expr, { ",", expr } ], ")" ;
variant         = identifier, ".", identifier, "(", [ expr, { ",", expr } ], ")" ;
restricted_map  = "RestrictedMap", "(", expr, [ ",", expr ], ")" ;
member          = identifier, ".", ( identifier | "*" ),
                  { ".", ( identifier | "*" ) } ;
list            = "[", [ expr, { ",", expr } ], "]" ;
tuple_or_group  = "(", expr, [ ",", expr, { ",", expr } ], ")" ;
map             = "#(", [ expr, "=>", expr, { ",", expr, "=>", expr } ], ")" ;

comp_op         = "==" | "!=" | "<" | "<=" | ">" | ">=" ;
add_op          = "+" | "-" ;
mul_op          = "*" | "/" ;
```

## Current Limits

Every rendered error and warning includes a stable lower-snake-case code in
brackets, for example `[missing_return]` or `[unused_variable]`. Tooling should
key behavior on that code rather than diagnostic prose, which may improve over
time. Erlang callers can obtain the same atoms with `diagnostics:code/1` and
`diagnostics:warning_code/1`. File extension and read failures use this same
coded diagnostic path.

Warnings are reported separately from errors and do not make checking, building,
or execution fail. The warning analysis currently reports unused variables,
unused parameters, variable shadowing, and ignored user-function return values.
Warnings are stored in the successful program AST under `warnings`, and
`terra check` renders them before its final `ok` message.

Immutable `temp Type` values have local function lifetime. Temporary-region
pointer slots instead live for the complete `Main` execution and are cleaned up
by the generated entry wrapper.
