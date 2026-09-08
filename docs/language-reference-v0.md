# Terra Language Reference v0

This document describes the implemented Terra v0 surface syntax. Terra is a
small research language that transpiles to Erlang source and runs on the BEAM
VM. The language should stay simple and grow incrementally.

## Program Shape

A Terra source file may begin with one optional `temp region(capacity);`
configuration, followed by module-scope imports, exports, Erlang external
signatures, `global` and `const` declarations, user type declarations, and
function declarations. Other `local`, `temp`, and ordinary statements are only
valid inside a function or block scope.
Every valid executable program must declare exactly one entry point:

```terra
function strict *SInt Main(*String Args) {
  return *SInt(0);
}
```

The entry point receives a temporary-region `*String Args` and returns a
temporary-region `strict *SInt`. The qualifier applies only to the returned
pointer. The generated `main/1` launcher owns the region: it
stores the converted platform arguments, calls Terra `Main`, dereferences and
validates the signed integer result, then cleans up in an `after` block. The
BEAM-facing result is an ordinary integer, never a pointer.

Module imports and exports are intentionally small and local:

```terra
import math_lib;

function strict *SInt Main(*String Args) {
  return *SInt(math_lib.Add(2, 3));
}
```

`import math_lib;` resolves only to a sibling file named `math_lib.terra`; there
is no package manager, version solving, or search path. Imported files are
checked as library modules, so they may omit `Main`. A library must explicitly
export any function another module should call:

```terra
export Add;

function Int Add(Int left, Int right) {
  return left + right;
}
```

Only exported functions are visible through qualified calls such as
`math_lib.Add(...)`. Structs, enums, globals, and constants remain local to the
source file in this version.

An `export Name;` declaration also emits a public Erlang wrapper. The generated
module name is `terra_` followed by the lowercase source-file base name, while
the function name is preserved as an exact Erlang atom. For `math_lib.terra`:

```erlang
terra_math_lib:'Add'(2, 3).
```

The wrapper validates each argument before entering Terra and validates the
result before returning it to Erlang. Invalid arguments raise
`{invalid_erlang_argument, Function, Position, ExpectedType, Value}`; an
unexpected internal result raises
`{invalid_terra_export_return, Function, ExpectedType, Value}`. Multiple Terra
returns become one tuple. Exported signatures may use every mapped concrete
type listed below, but not pointers, `Var`, or `State`. If the implementation
uses temporary-region pointers internally, the wrapper creates and cleans up a
region for that call.

### Erlang FFI

An Erlang call must be selected by an exact module-level `extern` signature:

```terra
extern Number erlang.lists.sum(List values);

function strict *SInt Main(*String Args) {
  return *SInt(erlang.lists.sum([1, 2, 3]));
}
```

The declaration records the Erlang module, function, arity, Terra parameter
types, and Terra return types. The compiler rejects calls to undeclared modules
or undeclared functions and checks arguments against the selected signature.
Code generation lowers the call directly to `module:function(...)`; it does not
perform implicit value conversion or verify that the installed Erlang/OTP
module implements the declared signature. Runtime failures propagate normally.

Terra values have one documented FFI representation:

| Terra type | Erlang term and boundary rule |
| --- | --- |
| `Number` | integer or float |
| `Int` | integer greater than or equal to zero |
| `SInt` | integer |
| `Float` | float |
| `Atom` | atom |
| `Bool` | atom `true` or `false` |
| `String` | UTF-8 binary |
| `Binary` | arbitrary binary |
| `PID` | process identifier |
| `Reference` | reference |
| `List` | list |
| `Tuple` | tuple |
| `Map` | map |
| `RestrictedMap` | `{terra_restricted_map, Capacity, Map}` with a valid non-negative capacity |
| named struct | map containing `'$terra_struct' => StructName`; fields use atom keys |
| named enum | map containing `'$terra_enum' => EnumName` and `tag => VariantName`; payload fields use atom keys |
| multiple returns | tuple whose elements follow declaration order |

Arguments already checked by Terra use these runtime representations directly.
Every external return is validated before entering Terra code, including each
element of a multiple-return tuple. A mismatch raises
`{invalid_erlang_return, Module, Function, ExpectedType, Value}`. External
signatures reject temporary-region pointers, inferred `Var`, and placeholder
`State`, because none has a stable cross-boundary value contract.

### OTP integration policy

OTP integration remains library-first. Typed `extern` declarations, Terra
modules, exported functions, and small Erlang callback adapters are preferred
over new behavior-specific syntax. Syntax is considered only for a recurring
pattern where the compiler can add a meaningful static guarantee and define
complete process, failure, and temporary-region semantics while lowering to
ordinary OTP APIs. Terra does not currently add syntax for supervisors,
applications, releases, or OTP behaviors. See
`docs/otp-integration-policy.md` for the maintained decision criteria.

### Standard-library boundary

Core compiler-backed helpers use lowercase `snake_case` and are available
without imports. Bundled library modules are explicit imports whose names use
the reserved `std_` prefix and lowercase `snake_case`; their public functions
use PascalCase, such as `std_string.Trim(value)`. The library adds no implicit
prelude, hidden import-time state, or alternate runtime. Its maintained scope,
naming, admission, and compatibility rules are documented in
`docs/standard-library-policy.md`.

### Process primitives

Terra has four built-in process operations:

```terra
local PID parent = self();
local PID worker = spawn(Worker(parent, "ready"));
send(worker, :continue);
local String reply = receive(String);
```

- `self()` returns the current BEAM process identifier.
- `spawn(Function(arguments))` accepts one direct call to a Terra function,
  evaluates its arguments in the parent, and runs it in a new BEAM process.
- `send(pid, value)` sends one value and returns the atom `:ok`.
- `receive(Type)` blocks for the next mailbox value, validates it, and returns
  it with the requested static type.

The receive type may be a concrete built-in type or a declared struct or enum.
A mismatched next message is consumed and raises
`{invalid_terra_message, ExpectedType, Value}`. The transfer rules are the same
as the FFI mapping: pointers, `Var`, and `State` cannot be messages or spawn
arguments. Each spawned process gets an independent temporary region when the
module uses pointers. Spawning is unlinked and unsupervised; links, monitors,
timeouts, selective receive, and OTP behavior remain library concerns.

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
Number Int SInt Float Atom Bool Map RestrictedMap List Tuple String Binary PID Reference State Var
```

Any built-in or user-defined type may be wrapped in temporary-region pointer
levels by prefixing one or more `*`, such as `*String`, `**Int`, or `***Player`.
`strict *Type` qualifies the outer pointer only and requires an explicitly
constructed pointer whose pointee type matches exactly.

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

String parsing helpers convert text to numeric values:

```terra
parse_int("12")       // Int
parse_sint("-12")     // SInt
parse_float("3.5")    // Float
parse_number("42")    // Number
```

They accept exactly one `String`. Invalid text fails explicitly at runtime with
`{invalid_conversion, string, Target, Value}` instead of producing a sentinel
value.

Formatting helpers convert scalar values to strings:

```terra
to_string(42)
to_string(:ready)
to_binary(true)
```

`to_string` and `to_binary` accept `Number`, `Int`, `SInt`, `Float`, `Atom`,
`Bool`, `String`, or `Binary`. `to_binary` returns `Binary` without imposing a
text encoding. `to_string` returns `String`; binary input must contain valid
UTF-8 or it fails with `{invalid_conversion, binary, string, Value}`.

`PID` and `Reference` are opaque immutable BEAM handles. They may be declared,
passed, returned, compared for equality, and used in FFI/export signatures, but
have no literal or constructor. For now, typed externals such as
`erlang.erlang.self()` and `erlang.erlang.make_ref()` create them. `Map` is the
native BEAM map representation already used by Terra map literals and updates.

### Absence, Failure, And Return Values

Terra keeps absence, failure, and returns separate:

- Absence is modeled as ordinary data. `null` and `nil` are rejected; use an
  enum variant such as `Result.Missing()` or an atom such as `:missing`.
- Failure is propagation, not a hidden optional value. `try` and `|>` preserve
  the original runtime failure for checked function/helper calls. Constructors
  and ordinary values do not need `try`.
- Returns are explicit values. Every function declares concrete return types,
  `return;` is rejected, and every control-flow path must return values matching
  the declaration.

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

Struct bodies may contain small inline `struct` or `enum` declarations. Inline
user types are registered by their declared name and can be used by later
fields, functions, constructors, and enum matches.

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

Each additional `*` adds another pointer level. Ordinary pointer declarations
fill in missing levels around a compatible initializer, while explicit prefix
stars construct those levels directly:

```terra
local **Int implicit = 1;
local **Int explicit = **1;
implicit.*.* = 7;
```

The `strict` qualifier applies to one pointer type, not a function or block.
It requires an explicit pointer value with an exactly matching pointee type and
does not apply ordinary numeric widening at that boundary:

```terra
local strict *Int exact = *1;
local strict **Int nested = **1;
```

`strict *SInt value = *1;` is invalid because the initializer is `*Int`; use
`*SInt(1)` to construct the exact expected pointee. A strict pointer has the
same checked runtime representation as an ordinary pointer and may alias the
same slot. Strictness is a compile-time construction and compatibility rule,
not a borrow checker or ownership mode.

The postfix `.*` helper reads a slot, and `pointer.* = value;` writes a
type-compatible value into it. Pointer types are valid in plain local variables,
function parameters and returns, call arguments, struct fields, and enum
payloads. Pointer allocation is rejected for `const`, `global`, and `temp`
storage. It is also kept separate from lazy, computed, atomic, and thread-local
storage so every pointer has one predictable region lifetime.

The optional first declaration `temp region(N);` sets a fixed capacity of `N`
pointer slots. Executables reserve one slot for `Main` arguments and necessarily
use another for the returned status, so fixed executable regions must have at
least two slots. A fixed capacity above 65,536 is rejected. Exceeding a fixed
region raises `terra_temporary_region_full`.

Without the declaration, the compiler includes the entry argument in its count
of pointer-producing expressions and records that count as an initial estimate.
The region may grow for loops and recursion, but never beyond 65,536 slots per
process; exceeding that ceiling raises `terra_temporary_region_limit`.

The generated `main/1` wrapper creates the process-local region before allocating
`Main` arguments and removes it in an `after` block on both success and failure.
Starting a nested region in the same process raises `terra_region_already_active`.
Each spawned Terra process creates and cleans up its own region. Pointer handles
contain their owner process, an unforgeable region reference, and a checked
non-negative slot. Missing regions or slots raise `terra_dangling_pointer`,
cross-process access raises `terra_cross_process_pointer`, and malformed handles
raise `terra_invalid_pointer`. Terra never exposes a raw machine address.

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

Immutable update expressions use braces after an existing map-like or struct
value:

```terra
local Player next = player{ score = 11 };
local Map changed = data{ :count => 2, key => "value" };
local RestrictedMap bounded = limited{ :status => "ready" };
```

An update returns a new value and leaves the original binding untouched. Struct
updates use `field = value`, require declared fields, and check replacement
types statically. Map and restricted-map updates use either `field = value` as
an atom-key shorthand or `key_expression => value`. Restricted-map updates keep
the original capacity and recheck it after applying the entries.

Function and constructor-style calls use parentheses:

```terra
Double(4)
List()
State()
```

`try` may prefix a checked function/helper call in any expression position or as
a standalone call:

```terra
local Int value = try LoadValue();
try Record(value);
return try Forward(value);
```

On success, `try` evaluates to the call's ordinary declared return value.
On failure, it re-raises the original BEAM exception with its reason and stack
unchanged, allowing `terra run` to retain the originating Terra source frame.
Constructors and non-call expressions reject `try`. Bare calls remain valid in
Terra v0 for compatibility; `try` documents and preserves explicit propagation.

The pipe operator passes its left value as the first argument of the checked
function/helper call on its right. Pipelines associate left-to-right:

```terra
return 2 |> Increment() |> Add(3);
```

This is equivalent to `Add(Increment(2), 3)`. Each stage is type checked using
the inserted first argument. A failure in the left expression or any called
stage propagates its original BEAM class, reason, stack, and Terra source frame.
The right side must be a checked function/helper call. A returned final
user-function stage continues to use Terra's tail-call dispatch.

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

The core console helpers provide compact standard-output and standard-error
writing:

```terra
print("score: ");
println(42);
eprint("warning: ");
eprintln(:retrying);
println();
```

`print` and `eprint` concatenate their arguments without a newline. `println`
and `eprintln` append one newline, including when called without arguments. All
four accept zero or more values and return the atom `:ok`. Strings are emitted
as UTF-8 text, scalar values use their ordinary spelling, and other values use
readable BEAM term formatting. Invalid UTF-8 binaries use BEAM term formatting
instead of being emitted as text.

`format(template, values...)` returns a `String` without writing it. Each `{}`
placeholder consumes one value from left to right; `{{` and `}}` escape literal
braces:

```terra
local String line = format("name={} score={} braces={{ok}}", "Ada", 42);
```

The first argument must be `String`. A different placeholder/value count raises
`{format_arity, Expected, Actual}`. An unmatched or unescaped brace raises
`{invalid_format_template, Template}`. Both failures compose with `try` and
pipeline propagation like other checked helper failures.

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
module_item     = import_decl | export_decl | extern_decl | struct_decl | enum_decl
                | module_decl | function_decl ;
import_decl     = "import", identifier, ";" ;
export_decl     = "export", identifier, ";" ;
extern_decl     = "extern", return_types, "erlang", ".", identifier, ".",
                  identifier, "(", [ params ], ")", ";" ;
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
value_type      = [ "strict" ], "*", { "*" }, type | type ;
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
pointer_write   = identifier, ".", "*", { ".", "*" }, "=", expr, ";" ;
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
                | remote_call
                | ffi_call
                | variant
                | member
                | list
                | tuple_or_group
                | map
                | restricted_map ;

call            = ordinary_call | self_call | spawn_call | send_call
                | receive_call ;
ordinary_call   = identifier, "(", [ expr, { ",", expr } ], ")" ;
self_call       = "self", "(", ")" ;
spawn_call      = "spawn", "(", ordinary_call, ")" ;
send_call       = "send", "(", expr, ",", expr, ")" ;
receive_call    = "receive", "(", type, ")" ;
remote_call     = identifier, ".", identifier, "(", [ expr, { ",", expr } ],
                  ")" ;
ffi_call        = "erlang", ".", identifier, ".", identifier, "(",
                  [ expr, { ",", expr } ], ")" ;
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
