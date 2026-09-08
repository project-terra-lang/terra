# Terra

Terra is a small research language with a Lua-like imperative syntax that
transpiles to Erlang and runs on the BEAM. It is aimed at programs such as game
servers and state machines, where immutable data and Erlang interoperability are
useful without exposing all of Erlang's syntax.

The project is deliberately incremental. Terra is not intended to become a
feature-complete general-purpose platform; each addition should remain small,
understandable, and compatible with the Erlang ecosystem.

## Project Status

- [x] Concurrent programming language with process and message primitives
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
function strict *SInt Main(*String Args) {
    stdout("hello from Terra");
    stdout(Args.*);
    return *SInt(0);
}
```

`Main` must accept `*String Args` and return `strict *SInt`. The `strict`
qualifier belongs to that return pointer, not to the function or its body. The
generated launcher
creates a temporary region, stores the platform arguments in it, passes their
pointer to `Main`, dereferences the returned status pointer, and then cleans up
the region. The BEAM-facing `main/1` therefore returns an ordinary signed
integer; no temporary pointer escapes its lifetime. Terra has no `void` type,
so every function returns a real value.

Terra modules can import sibling source files without a package manager:

```terra
import math_lib;

function strict *SInt Main(*String Args) {
    return *SInt(math_lib.Add(2, 3));
}
```

An import named `math_lib` resolves to `math_lib.terra` in the same directory.
Imports whose name starts with the reserved `std_` prefix resolve to bundled
standard-library files, such as `std/std_collection.terra`. Imported functions
must be explicitly exported by the imported module:

```terra
export Add;

function Int Add(Int left, Int right) {
    return left + right;
}
```

Only exported functions are callable as `module.Function(...)`. Imported library
files may omit `Main`; executable files still keep the fixed `Main` entry point.

The same declaration exposes a checked Erlang-facing wrapper. Terra preserves
the source function name as an exact Erlang atom and derives the BEAM module
name from the file:

```erlang
terra_math_lib:'Add'(2, 3).
```

Wrapper arguments and returns use the term mapping below and are validated at
runtime. Invalid Erlang arguments raise `invalid_erlang_argument`; an impossible
Terra-side return mismatch raises `invalid_terra_export_return`. Functions with
pointer, `Var`, or `State` parameters or returns cannot be exported.

## Erlang FFI

Terra can call a deliberately selected Erlang function after declaring its
Terra-facing signature at module scope:

```terra
extern Number erlang.lists.sum(List values);

function strict *SInt Main(*String Args) {
    local List values = [1, 2, 3];
    return *SInt(erlang.lists.sum(values));
}
```

Each `extern` declaration selects exactly one Erlang module/function pair and
defines the argument and return types Terra will check. Calls without a matching
declaration are rejected. Values cross the boundary without hidden conversion:

| Terra value | Erlang term |
| --- | --- |
| `Number` | integer or float |
| `Int` | non-negative integer |
| `SInt` | integer |
| `Float` | float |
| `Atom` | atom |
| `Bool` | `true` or `false` atom |
| `String` | UTF-8 binary |
| `Binary` | arbitrary binary |
| `PID` | process identifier |
| `Reference` | reference |
| `List`, `Tuple`, `Map` | list, tuple, map |
| `RestrictedMap` | `{terra_restricted_map, Capacity, Map}` |
| `struct Name` | map with `'$terra_struct' => 'Name'` and atom field keys |
| `enum Name` | map with `'$terra_enum' => 'Name'`, an atom `tag`, and atom payload keys |
| multiple returns | tuple in declared return order |

FFI returns are checked at runtime against the declared Terra type. A mismatch
raises `invalid_erlang_return` before the value can enter ordinary Terra code.
Temporary-region pointers, `Var`, and the placeholder `State` type cannot cross
the FFI boundary.

### OTP Integration Policy

OTP integration is library-first. Prefer typed `extern` calls, ordinary Terra
modules, exported Terra functions, or a small Erlang callback adapter before
adding language syntax for an OTP behavior. New syntax must provide a repeated,
useful static guarantee with clear process, failure, and temporary-region
semantics; shortening a library call is not enough.

Terra's process primitives remain a small foundation rather than replacements
for supervisors, applications, releases, links, monitors, or behaviors. The
complete decision rule is recorded in
[docs/otp-integration-policy.md](docs/otp-integration-policy.md), with a runnable
checked-FFI example in
[examples/otp_library_first.terra](examples/otp_library_first.terra).

## Standard Library Policy

Terra's standard library is intentionally tiny. Compiler-backed core helpers
use lowercase `snake_case` and require no import. Ordinary bundled modules are
explicitly imported, use the reserved `std_` prefix with lowercase
`snake_case` names, and expose PascalCase functions, for example
`std_string.Trim(value)`.

Library additions must cover common work, have concise typed semantics, compose
with immutable values and explicit failure propagation, and remain thin Terra
or Erlang/OTP wrappers whenever compiler support is unnecessary. There is no
implicit prelude beyond core helpers, and broad frameworks remain outside the
standard library. The complete admission, naming, module, testing, and v0
compatibility rules are in
[docs/standard-library-policy.md](docs/standard-library-policy.md).

Bundled modules are ordinary Terra files backed by checked Erlang FFI wrappers
where useful:

```terra
import std_collection;
import std_string;
import std_binary;
import std_time;
import std_random;
import std_fs;
import std_test;

function strict *SInt Main(*String Args) {
    local List values = [1, 2, 3];
    local String name = std_string.Trim(" Terra ");
    local Binary bytes = to_binary(name);
    println(format("count={} sum={}",
                   std_collection.Length(values),
                   std_collection.Sum(values)));
    println("reversed: ", std_collection.Reverse(values));
    println(format("name={} bytes={} now={}",
                   std_string.Uppercase(name),
                   std_binary.ByteSize(bytes),
                   std_time.SystemMillisecond()));
    println("readme present: ", std_fs.IsFile("README.md"));
    local Atom ok = std_test.EqualInt(std_collection.Length(values), 3, "example count");
    stdout(ok);
    return *SInt(std_collection.Length(values));
}
```

Current modules include:

| Module | Functions |
| --- | --- |
| `std_collection` | `Length(List) -> Int`, `Sum(List) -> Number`, `Reverse(List) -> List`, `IsEmpty(List) -> Bool` |
| `std_string` | `ByteSize(String) -> Int`, `Trim(String) -> String`, `Uppercase(String) -> String`, `Lowercase(String) -> String` |
| `std_binary` | `ByteSize(Binary) -> Int`, `IsEmpty(Binary) -> Bool` |
| `std_time` | `MonotonicMillisecond() -> SInt`, `SystemMillisecond() -> SInt` |
| `std_random` | `Uniform(Int) -> Int` |
| `std_fs` | `IsFile(String) -> Bool`, `IsDir(String) -> Bool` |
| `std_test` | `Assert(Bool, String) -> Atom`, `Refute(Bool, String) -> Atom`, typed `Equal...` helpers for `Int`, `SInt`, `Number`, `Float`, `String`, `Binary`, `Atom`, and `Bool` |

`std_random.Uniform(limit)` follows Erlang's `rand:uniform/1` contract and
returns an integer from `1` through `limit`.
`std_test` helpers return `:ok` on success and raise
`{:assertion_failed, Message}` on failure, so Terra test programs can use the
same explicit runtime failure path as other checked helpers.

## Types

Terra currently supports:

- Numbers: `Number`, `Int`, `SInt`, and `Float`
- Scalars: `Atom` and `Bool`
- Collections: `Map`, `RestrictedMap`, `List`, and `Tuple`
- Text and bytes: `String` and `Binary`
- BEAM handles: `PID` and `Reference`
- User data: `struct` and `enum`
- Temporary-region pointers: `*Type`, `**Type`, and deeper pointer types
- Strict pointer contracts: `strict *Type`

`Var` asks the compiler to infer a concrete type. `State` is reserved as a
placeholder for future state-machine work.

`Number` accepts integers and floats. `Int` represents non-negative integer
intent, while `SInt` represents signed integer intent. Both use BEAM
arbitrary-precision integers at runtime. Terra follows Erlang numeric semantics:
`/` produces a float and `div` performs integer division.

Terra has no `null`, `nil`, or `undefined` value. Model absence explicitly with
an enum variant or an atom.

The value rules are deliberately small:

- Absence is data. Use an enum variant or atom instead of `null`.
- Failure is propagation. Use `try` or `|>` with checked function/helper calls;
  invalid conversions and runtime failures raise explicit errors.
- Returns are values. Every function declares a concrete return type and every
  path returns values matching that declaration.

Safe conversion helpers keep parsing and formatting explicit:

```terra
local Int port = parse_int("8080");
local Float ratio = parse_float("0.5");
local Number count = parse_number("42");
local String label = to_string(port);
local Binary bytes = to_binary(:ready);
```

`parse_int`, `parse_sint`, `parse_float`, and `parse_number` accept `String`
input and fail explicitly on invalid text. `to_binary` returns arbitrary BEAM
bytes as `Binary`; `to_string` returns UTF-8 `String` and accepts `Binary` only
when its bytes are valid UTF-8.

Console helpers provide compact output and simple interpolation:

```terra
print("score: ");
println(42);
eprintln("could not load save data");
local String message = format("player={} score={} braces={{ok}}", "Ada", 42);
```

`print` and `eprint` write to standard output and standard error without a
newline. `println` and `eprintln` append one newline; calling either with no
arguments writes a blank line. Arguments are concatenated in order and each
helper returns `:ok`. `format` replaces each `{}` from left to right and returns
a `String`; `{{` and `}}` produce literal braces. A malformed template or a
placeholder/value count mismatch fails explicitly. Strings print as text,
scalars use their ordinary spelling, and compound values use readable BEAM term
formatting. `stdout(...)` remains available and continues to print each argument
on its own line.

`PID` and `Reference` are opaque, immutable BEAM values. They have no type
constructor; `self()` and `spawn(...)` produce PIDs, while typed FFI calls can
produce either handle. `Map` continues to use a native BEAM map, including
across FFI and exported-function boundaries.

## Processes and Messages

Terra exposes a small set of BEAM process primitives without adding lambdas or
a second function model:

```terra
function Atom Worker(PID parent) {
    send(parent, :ready);
    local String reply = receive(String);
    send(parent, reply);
    return :done;
}

function strict *SInt Main(*String Args) {
    local PID worker = spawn(Worker(self()));
    local Atom ready = receive(Atom);
    send(worker, "ack");
    local String reply = receive(String);
    return *SInt(1);
}
```

`self()` returns the current process PID. `spawn(Function(arguments))` evaluates
the arguments in the parent and starts that direct Terra function call in a new
BEAM process. `send(pid, value)` sends one immutable transferable value and
returns `:ok`. `receive(Type)` blocks for the next mailbox message, validates it
against the concrete built-in, struct, or enum type, and returns it. A mismatch
raises `invalid_terra_message` after consuming that message.

Pointers, `Var`, and `State` cannot be sent or captured as spawn arguments.
When a module uses temporary pointers, each spawned process receives and cleans
up its own temporary region. These primitives intentionally provide no links,
monitors, supervisors, registered names, selective patterns, or timeouts; those
remain available through Erlang/OTP libraries until a smaller Terra abstraction
proves useful. See [examples/processes.terra](examples/processes.terra).

## Immutable Variables

Bindings cannot be reassigned after declaration.

```terra
const Int max_players = 64;
global String region = "eu-west";

function strict *SInt Main(*String Args) {
    local const Int retries = 3;
    local computed Int attempts = retries + 1;
    local lazy Number delayed = 42;
    local atomic Int counter = 1;
    local thread_local String session = "ready";
    temp String message = session;
    stdout(message, Args.*);
    return *SInt(attempts);
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

Each `*` adds one pointer level. Reads and writes use one `.*` per level:

```terra
local **Int score = 1;
score.*.* = 42;
stdout(score.*.*);
```

Ordinary pointer declarations may allocate missing pointer levels around a
compatible value. `strict` qualifies only the outer pointer and requires an
explicit pointer value whose pointee type matches exactly:

```terra
local strict *Int exact = *1;
local strict **Int nested = **1;
```

For example, `strict *SInt value = *1;` is rejected because `*1` is `*Int`;
write `*SInt(1)` when that exact pointee type is intended. Strict pointers use
the same checked temporary-region handles at runtime and still allow aliasing;
the qualifier is a compile-time construction and type-compatibility contract.

Pointer types may be used in function parameters and returns, function
arguments, struct fields, and enum payloads. Pointer allocation is allowed only
for plain `local` declarations; `const`, `global`, and `temp` declarations stay
immutable and cannot use pointer storage.

Programs may set a fixed number of pointer slots with a first module-level
declaration:

```terra
temp region(64);
```

For an executable, capacity includes the `Main` argument slot and every pointer
allocated by Terra code, including the returned status pointer. Fixed regions
must contain at least two slots and may contain at most 65,536 slots per process.
Without a declaration, the compiler records an allocation estimate and permits
growth up to the same 65,536-slot safety ceiling. Fixed exhaustion raises
`terra_temporary_region_full`; automatic exhaustion raises
`terra_temporary_region_limit`.

Only one region may be active in a process at a time. The region exists for one
`Main` or spawned-process execution and is always cleaned up after success or
failure. Handles contain an owning PID, unforgeable region reference, and
checked non-negative slot. Missing regions, stale slots, malformed handles, and
cross-process access fail explicitly instead of reaching the underlying map or
becoming dangling pointers.

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

Struct and enum bodies may contain small inline `struct` or `enum`
declarations. Inline user types are registered by their declared name and can be
used by later fields, functions, constructors, and enum matches:

```terra
struct Socket {
    SockAddr address;

    enum SockAddr {
        Addr(String host);
        Closed;
    }
}
```

Enum payload constructors are declared in the enum body, either with the
explicit `variant` keyword or the shorter bare variant form. They are not
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

Maps, restricted maps, and structs support immutable update expressions:

```terra
local Player next = player{ score = 11 };
local Map changed = data{ :count => 2, :dynamic_key => "value" };
local RestrictedMap bounded = limited{ :status => "ready" };
```

Updates return a new value and leave the original binding untouched. Struct
updates require declared field names and type-compatible values. Restricted map
updates keep the original capacity and fail if new keys would exceed it.

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
- `try` invokes a checked function/helper call with explicit failure propagation.

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
fmt <file>                Format a Terra source file in place
fmt --check <file>        Check whether a Terra source file is formatted
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

`terra fmt` is intentionally small and AST-based. It rewrites valid Terra
source into the compiler's canonical style with four-space indentation, spaced
operators, normalized declarations, and one final newline. This first formatter
does not preserve comments.

The examples directory contains focused programs for structs, enums, maps,
loops, diagnostics, recursion, and the larger feature showcase.
