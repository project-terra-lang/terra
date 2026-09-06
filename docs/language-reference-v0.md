# Terra Language Reference v0

This document describes the implemented Terra v0 surface syntax. Terra is a
small research language that transpiles to Erlang source and runs on the BEAM
VM. The language should stay simple and grow incrementally.

## Program Shape

A Terra source file contains function declarations only. Every valid program
must declare exactly one entry point:

```terra
function Number Main(String Args) {
  return 0;
}
```

The entry point receives command-line arguments as `String Args` and returns a
`Number`.

The current compiler pipeline is split into explicit passes:

```text
parsing -> name_resolution -> type_checking -> unreachable_code -> definite_return -> lowering -> codegen
```

`program:parse_file/1` runs the frontend passes and records them in the
program AST. `transpiler:codegen_pass/1` turns that lowered AST into Erlang
source.

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
Number Int SInt Float Atom Bool Map List Tuple String State Var
```

`Number` accepts `Int`, `SInt`, and `Float` values. `Var` asks the compiler to
infer the concrete type from the initializer. `State` is currently accepted as a
research placeholder type for future runtime state semantics.

### Numeric Semantics

`Int` and `SInt` both use BEAM arbitrary-precision integers. `SInt` marks
explicitly signed source values, including negative literals, but neither type
is a statically checked numeric range. Integer arithmetic therefore does not
wrap or overflow. `Float` uses the BEAM floating-point representation; its
precision and exceptional arithmetic behavior follow the Erlang runtime.

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
local Int count = 10;
global State state = State();
temp String label = "debug";
```

Supported declaration scopes are `global`, `local`, and `temp`. Supported
declaration modifiers are:

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
parsing. `computed`, `atomic`, `thread_local`, `global`, and `temp` currently
preserve metadata for later compiler stages unless explicitly supported by
codegen.

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

Function and constructor-style calls use parentheses:

```terra
Double(4)
List()
State()
```

Member access chains use dots and currently infer to `Var`:

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

### Loops

`for_each` iterates over `List`, `Tuple`, `Map`, and `String` values. The body
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
program         = { function_decl } ;
function_decl   = "function", return_types, identifier, "(", [ params ], ")",
                  block ;
return_types    = type | "(", type, { ",", type }, ")" ;
params          = param, { ",", param } ;
param           = type, identifier ;
block           = "{", { statement }, "}" ;

statement       = var_decl
                | destructure_decl
                | multi_binding
                | return_stmt
                | call_stmt
                | once_call_stmt
                | if_stmt
                | unless_stmt
                | switch_stmt
                | for_each_stmt
                | for_range_stmt
                | while_stmt
                | do_while_stmt ;

var_decl        = scope, [ modifier ], type, identifier, "=", expr, ";" ;
destructure_decl = scope, "(", binding, { ",", binding }, ")", "=", expr, ";" ;
multi_binding   = scope, binding, ",", binding, { ",", binding }, "=", expr, ";" ;
binding         = type, identifier ;
scope           = "global" | "local" | "temp" ;
modifier        = "lazy" | "const" | "computed" | "atomic" | "thread_local" ;

return_stmt     = "return", expr, { ",", expr }, ";" ;
call_stmt       = call, ";" ;
once_call_stmt  = identifier, ";" ;

if_stmt         = "if", expr, block, { "elseif", expr, block },
                  [ "else", block ] ;
unless_stmt     = "unless", expr, block, [ "else", block ] ;
switch_stmt     = "if", expr, "==", "{", case_clause, { case_clause },
                  default_case, "}" ;
case_clause     = "case", expr, ":", { statement } ;
default_case    = "case", ":", { statement } ;

for_each_stmt   = "for_each", identifier, "in", expr, block ;
for_range_stmt  = "for", call_to_range, block ;
while_stmt      = "while", expr, block ;
do_while_stmt   = "do_while", expr, block ;

expr            = logical_or ;
logical_or      = logical_and, { "||", logical_and } ;
logical_and     = comparison, { "&&", comparison } ;
comparison      = additive, [ comp_op, additive ] ;
additive        = multiplicative, { add_op, multiplicative } ;
multiplicative  = unary, { mul_op, unary } ;
unary           = [ "!" | "-" ], unary | primary ;
primary         = literal
                | identifier
                | call
                | member
                | list
                | tuple_or_group
                | map ;

call            = identifier, "(", [ expr, { ",", expr } ], ")" ;
member          = identifier, ".", identifier, { ".", identifier } ;
list            = "[", [ expr, { ",", expr } ], "]" ;
tuple_or_group  = "(", expr, [ ",", expr, { ",", expr } ], ")" ;
map             = "#(", [ expr, "=>", expr, { ",", expr, "=>", expr } ], ")" ;

comp_op         = "==" | "!=" | "<" | "<=" | ">" | ">=" ;
add_op          = "+" | "-" ;
mul_op          = "*" | "/" ;
```

## Current Limits

Warnings and real `global`/`atomic`/`thread_local` runtime behavior are future
work.
