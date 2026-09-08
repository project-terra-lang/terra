# Standard Library Policy

Terra's standard library stays small, explicit, and compatible with Erlang/OTP.
It should make routine Terra programs pleasant without becoming a second runtime
or hiding useful BEAM behavior.

## What Belongs

A standard-library operation should satisfy all of these rules:

- It solves a common task in small programs, game servers, or state machines.
- Its behavior and types can be explained in a short reference entry.
- It has deterministic cross-platform semantics, or documents the relevant OS
  result explicitly.
- It composes with immutable values, concrete return types, and `try` or `|>`
  failure propagation.
- It can be implemented as a small Terra wrapper or a thin checked Erlang/OTP
  call, unless compiler support is required for type or runtime safety.
- It has focused parser/type tests when compiler-backed and BEAM execution tests
  for observable behavior.

Prefer a focused operation over a broad framework. Do not duplicate OTP
supervision, networking stacks, package management, deployment, observability,
or application lifecycle tooling in the standard library.

## Layers

The library has two deliberately small layers:

1. Core helpers are available without imports only when the compiler must know
   their types or semantics. Existing examples are `stdout`, `parse_int`,
   `to_string`, `print`, `println`, `eprint`, `eprintln`, `format`, `self`,
   `spawn`, `send`, and typed `receive`.
2. Bundled modules contain ordinary reusable operations and must be imported
   explicitly. They should be Terra modules or thin checked OTP wrappers.

There is no implicit prelude beyond core helpers. Bundled modules must not own
hidden global state, start processes on import, or allocate temporary pointers
that escape a call.

## Naming

- Core helper names use lowercase `snake_case`, such as `parse_int` and
  `to_binary`.
- Bundled module filenames and import names use lowercase `snake_case` with the
  reserved `std_` prefix, such as `std_console` and `std_string`.
- Public functions in bundled modules use PascalCase, matching ordinary Terra
  functions: `std_string.Trim(value)`.
- Structs, enums, and enum variants use PascalCase.
- Parameters, local values, fields, and constants use lowercase `snake_case`.
- Atoms use lowercase `snake_case` unless an Erlang boundary requires a specific
  atom.
- Predicates should read as questions with an `Is` or `Has` prefix, such as
  `IsEmpty` or `HasPrefix`.
- Fallible operations keep the direct operation name and fail explicitly; avoid
  suffix pairs such as `Parse` and `TryParse` unless they return different,
  documented data types.

Names should use full domain words where practical. Avoid aliases for the same
operation, type-encoded names where static types already distinguish behavior,
and abbreviations other than established terms such as UTF-8.

## Initial Module Set

The planned surface is intentionally bounded:

| Module | Responsibility |
| --- | --- |
| `std_console` | Higher-level console interaction beyond core printing |
| `std_format` | Formatting beyond core `{}` interpolation |
| `std_collection` | Small list, tuple, and map helpers |
| `std_string` | UTF-8 string operations |
| `std_binary` | Arbitrary binary operations |
| `std_time` | Monotonic/system time and simple durations |
| `std_random` | Explicit random operations |
| `std_fs` | Small filesystem operations |
| `std_test` | Assertions and tiny test support |

A module is added only when its first useful operations are implemented; empty
placeholder modules are not part of the library.

Current bundled modules:

| Module | Functions |
| --- | --- |
| `std_collection` | `Length(List) -> Int`, `Sum(List) -> Number`, `Reverse(List) -> List`, `IsEmpty(List) -> Bool` |

## Compatibility

During Terra v0, additions should be incremental and existing names should not
be silently repurposed. A behavior change must update the language reference,
examples, and regressions in the same change. Boundary values continue to use
Terra's documented Erlang term mapping, and platform failures remain explicit
rather than being converted to null-like sentinels.
