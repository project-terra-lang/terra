# Terra Roadmap

Terra should stay a small, readable BEAM language: Lua-like in feel, Erlang-
friendly in runtime behavior, and powerful through a focused feature set rather
than a large compiler or production framework. This is a research project, so
new features should arrive in small, understandable steps.

## Current Baseline

- [x] Fixed `function Number Main(String Args)` entry point
- [x] Immutable variables, type inference, shadowing, lazy and computed values
- [x] Tuple destructuring and multiple function return values
- [x] Functions, checked calls, recursion, and once-only calls
- [x] Conditions, exhaustive switches, and loops
- [x] `stdout(...)` console output intrinsic
- [x] Friendly diagnostics and `terra explain`
- [x] Erlang source generation and BEAM compilation/execution
- [x] Stable diagnostic codes, source spans, and deterministic compiler output
- [x] `try` calls and pipe-based failure propagation with `|>`
- [x] `Map` / `RestrictedMap` count and member inspection
- [x] End-to-end feature showcase

## Milestone 1: Keep the Compiler Solid (Complete)

- [x] Write a versioned Terra grammar and language reference
- [x] Split parsing, name resolution, type checking, lowering, and codegen into
      explicit compiler passes
- [x] Replace raw-token and `unparsed_statement` AST fallbacks
- [x] Add lexical block scopes and verify that branch/loop bindings never leak
- [x] Add definite-return and unreachable-code analysis
- [x] Complete expression precedence, unary operators, boolean operators, and
      short-circuit evaluation
- [x] Define integer overflow, numeric conversion, division, and comparison rules
- [x] Make tail-recursive calls compile to real BEAM tail calls
- [x] Define and implement exact semantics for `name;` once-only calls
- [x] Implement real semantics for `global`, `atomic`, `thread_local`, and
      `computed`
- [x] Add warnings separately from errors
- [x] Preserve generated Erlang source maps so runtime failures point back to Terra

## Milestone 2: Testing and Examples (Complete)

- [x] Create one command that builds and runs every test suite
- [x] Add unit tests for tokenizer, parser, type-checker, and codegen rules
- [x] Add golden tests for generated Erlang source and diagnostics
- [x] Add a few end-to-end tests that compile and run Terra programs on BEAM
- [x] Establish regression tests as part of fixing compiler bugs
- [x] Bring `examples/feature_showcase.terra` up to date with the supported language
- [x] Add one or two small real examples, such as a CLI counter or tiny text game

## Milestone 3: Small Powerful Language Features

- [x] Add user-defined records/structs for plain data
- [x] Add tagged unions or enums for simple state machines and results
- [ ] Add pattern matching only where it keeps code clearer than nested branches
- [ ] Add immutable update syntax for maps, restricted maps, and records
- [ ] Add simple module-level imports/exports without a package manager
- [ ] Add safe numeric/string/binary conversion helpers
- [ ] Keep nullability, failure propagation, and return-value rules easy to explain

## Milestone 4: Erlang and BEAM Interop

- [ ] Add an explicit Erlang FFI for calling selected Erlang modules/functions
- [ ] Map Terra values predictably to Erlang terms
- [ ] Allow Erlang code to call exported Terra functions
- [ ] Support the BEAM types Terra needs most: binaries, PIDs, references, and maps
- [ ] Add lightweight process spawning and message send/receive as language/library
      primitives
- [ ] Keep OTP integration library-first unless syntax clearly earns its place

## Milestone 5: Tiny Standard Library and Tooling

- [ ] Define a small standard-library policy and naming convention
- [ ] Add `print`, formatting, and basic console helpers on top of `stdout`
- [ ] Add practical collection, string, binary, time, random, and filesystem helpers
- [ ] Add a tiny testing/assertion library for Terra programs
- [ ] Add `terra fmt` after the syntax feels stable enough
- [ ] Improve `terra explain` with inferred types and clearer control-flow notes
- [ ] Keep editor/tooling work minimal until the language stops changing quickly

## Ongoing Practices

- Keep simplifying compiler internals as features settle
- Update `docs/language-reference-v0.md` whenever syntax or semantics change
- Add a regression test with each compiler bug fix
- Keep `examples/feature_showcase.terra` current as the language evolves

## Parked Ideas

These may be useful later, but they are intentionally not active milestones:

- Full OTP application generation, supervisors, releases, and operations tooling
- Networking stacks, WebSockets, matchmaking, authoritative game-room libraries,
  load bots, and distributed server infrastructure
- Package publishing, dependency locking, language-server support, and debugger
  workflows
- Production observability, OpenTelemetry, hot-code upgrades, deployment, and
  security hardening
- Large resource-analysis systems beyond simple warnings for obviously risky
  recursion, loops, or process usage

If Terra grows toward any of these, do it one small library or example at a time.
