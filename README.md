# Terra

Terra is a small research language with a Lua-like imperative syntax that
transpiles to Erlang and runs on the BEAM. It is aimed at programs such as game
servers and state machines, where immutable data and Erlang interoperability are
useful without exposing all of Erlang's syntax.

The project is deliberately incremental. Terra is not intended to become a
feature-complete general-purpose platform; each addition should remain small,
understandable, and compatible with the Erlang ecosystem.

## Project Status

- [ ] Concurrent programming language with process and message primitives
- [x] Immutable-by-default state with temporary-region fake mutability
- [x] Turing-complete core through conditionals, recursion, and unbounded integers
- [ ] Small standard library
- [x] Imperative source language that compiles to Erlang and runs on the BEAM

Unchecked items are active directions, not promises of a large framework. See
[TODO.md](TODO.md) for the remaining milestones and [Progress.md](Progress.md)
for completed work.

## Quick Start

Terra requires Erlang/OTP with `erlc`, `erl`, and `escript` available on your
`PATH`.

```sh
./build.sh --build
./run.sh check examples/feature_showcase.terra
./run.sh run examples/feature_showcase.terra hello from terra
```

Run the test suite with:

```sh
./build.sh --test
```

For a smaller example:

```sh
./run.sh run examples/counter.terra
```

## Program Shape

Every executable Terra file has one fixed entry point:

```terra
function Number Main(String Args) {
    stdout("hello from Terra");
    return 0;
}
```

`Main` must accept `String Args` and return `Number`. Terra has no `void` type,
so every function returns a real value.

## Types

Terra currently supports:

- Numbers: `Number`, `Int`, `SInt`, and `Float`
- Scalars: `Atom` and `Bool`
- Collections: `Map`, `RestrictedMap`, `List`, and `Tuple`
- Strings: `String`
- User data: `struct` and `enum`
- Temporary-region pointers: `*Type`

`Var` asks the compiler to infer a concrete type. `State` is reserved as a
placeholder for future state-machine work.

`Number` accepts integers and floats. `Int` represents non-negative integer
intent, while `SInt` represents signed integer intent. Both use BEAM
arbitrary-precision integers at runtime. Terra follows Erlang numeric semantics:
`/` produces a float and `div` performs integer division.

Terra has no `null`, `nil`, or `undefined` value. Model absence explicitly with
an enum variant or an atom.

## Immutable Variables

Bindings cannot be reassigned after declaration.

```terra
const Int max_players = 64;
global String region = "eu-west";

function Number Main(String Args) {
    local const Int retries = 3;
    local computed Int attempts = retries + 1;
    local lazy Number delayed = 42;
    local atomic Int counter = 1;
    local thread_local String session = "ready";
    temp String message = session;
    stdout(message);
    return attempts;
}
```

Declarations and evaluation modifiers include:

- `const` and `global` at module scope
- `local` and `temp` inside functions
- `const`, `computed`, `lazy`, `atomic`, and `thread_local` on local bindings

Function parameters and local bindings use lexical block scope.

## Fake Mutability

Terra pointers provide explicit fake mutability while ordinary values remain
immutable. A pointer owns one slot in a process-local temporary region:

```terra
local *String name = "initial";
name.* = "Terra";
stdout(name.*);
```

Prefix `*` creates a pointer from an existing value. This copies the value into
a new region slot; it does not expose a raw BEAM memory address:

```terra
local String original = "Ada";
local *String name = *original;
```

Pointer types may be used in function parameters and returns, function
arguments, struct fields, and enum payloads. Pointer allocation is allowed only
for plain `local` declarations; `const`, `global`, and `temp` declarations stay
immutable and cannot use pointer storage.

Programs may set a fixed number of pointer slots with a first module-level
declaration:

```terra
temp region(64);
```

Without that declaration, the compiler estimates the initial region size from
the program's pointer-producing expressions and permits growth for repeated or
recursive calls. A fixed region reports an error if its slot capacity is
exceeded. The region exists for one `Main` execution and is always cleaned up
after success or failure. Handles are tagged with their owner process and region;
stale and cross-process pointers are rejected instead of being dereferenced.

Run the complete pointer example with:

```sh
./run.sh run examples/fake_mutability.terra player-session
```

## Plain Data

Struct declarations define named fields. Constructor arguments are positional
and follow declaration order:

```terra
struct Player {
    String name;
    Int score;
}

local Player player = Player("Ada", 10);
stdout(player.name);
```

Enum payload constructors are declared explicitly with `variant`. They are not
created magically by the compiler:

```terra
enum Result {
    variant Ok(Int value);
    variant Error(String message);
    variant Pending;
}

local Result result = Result.Ok(42);
```

Structs and enum values compile to tagged Erlang maps, so generated values stay
easy to inspect and exchange with Erlang code.

## Functions And Failure

Functions declare parameter and return types. Multiple return values compile to
an Erlang tuple:

```terra
function (Int, Int) divide(Int left, Int right) {
    return left div right, left % right;
}
```

Terra has three call forms:

```terra
local Int value = calculate();
calculate;
local Result attempted = try risky_call();
```

- A normal call returns the function's value.
- A bare zero-argument function name invokes it successfully at most once per
  generated module and BEAM process.
- `try` invokes a user function with explicit failure propagation.

The pipe operator passes the left value as the first argument of the call on the
right:

```terra
local Int result = 5 |> add(3) |> multiply(2);
```

## Conditions And Matching

Terra supports `if`, `elseif`, `else`, `unless`, and exhaustive switch
expressions. A switch uses `if subject == { ... }` and ends with `case:`:

```terra
if score >= 100 {
    stdout("high score");
} elseif score >= 50 {
    stdout("getting there");
} else {
    stdout("keep going");
}

if status == {
    case "ready":
        stdout("starting");
    case:
        stdout("waiting");
}
```

Enum cases can bind their payload fields:

```terra
if result == {
    case Result.Ok(bind value):
        stdout(value);
    case Result.Error(bind message):
        stdout(message);
    case Result.Pending():
        stdout("pending");
    case:
        stdout("unknown result");
}
```

Use `_` for an ignored enum payload. Function calls are valid in switch case
expressions and inside case bodies.

Comments use either `--` or `//`:

```terra
-- Lua-style comment
// C-style line comment
```

## Collections And Loops

Maps support atom keys, string keys, dynamic keys, and member lookup:

```terra
local Map scores = #(:alice => 10, "bob" => 12);
local Int alice = scores.alice;
```

Restricted maps add an immutable member-capacity limit:

```terra
local RestrictedMap scores = RestrictedMap(3, #("alice" => 10));
```

Loops include collection iteration, numeric ranges, `while`, and `do while`:

```terra
for_each name in names {
    stdout(name);
}

for range(5) {
    stdout(it);
}

while ready {
    tick();
}

do_while ready {
    tick();
}
```

Loops lower to recursive Erlang helper functions, preserving Terra's immutable
binding model.

## Compiler Commands

After building, invoke the compiler through `./run.sh`:

```text
check <file>              Parse and type-check a Terra source file
tokens <file>             Print tokenizer output
ast <file>                Print the parsed abstract syntax tree
explain <file>            Show inferred and declared program information
emit <file> [output.erl]  Generate Erlang source
build <file> [build-dir]  Generate and compile a BEAM module
run <file> [args...]      Build and execute Main
types                     List built-in Terra types
version                   Print the compiler version
help                      Show command help
```

Generated Erlang and BEAM files are written to the build directory. Diagnostics
include stable error codes, source locations, contextual labels, suggestions,
and generated Erlang-to-Terra source mapping where available. Builds are
deterministic for the same source and compiler version.

The examples directory contains focused programs for structs, enums, maps,
loops, diagnostics, recursion, and the larger feature showcase.
