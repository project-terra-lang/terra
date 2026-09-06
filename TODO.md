# Terra Roadmap

Terra should grow into a small, reliable BEAM language first. Game-server
features should generally be libraries built on stable language, OTP, process,
networking, and binary-data primitives rather than special syntax in the
compiler.

## Current Baseline

- [x] Fixed `function Number Main(String Args)` entry point
- [x] Immutable variables, type inference, shadowing, lazy and computed values
- [x] Tuple destructuring and multiple function return values
- [x] Functions, checked calls, recursion, and once-only calls
- [x] Conditions, exhaustive switches, and loops
- [x] `stdout(...)` console output intrinsic
- [x] Friendly diagnostics and `terra explain`
- [x] Erlang source generation and BEAM compilation/execution
- [x] End-to-end feature showcase

## Milestone 1: Make the Compiler Trustworthy

- [X] Write a versioned Terra grammar and language reference
- [X] Add source spans to every token and AST node
- [X] Make parser diagnostics use exact spans instead of source-search heuristics
- [X] Replace all raw-token and `unparsed_statement` AST fallbacks
- [X] Split parsing, name resolution, type checking, lowering, and codegen into
      explicit compiler passes
- [X] Add lexical block scopes and verify that branch/loop bindings never leak
- [X] Add definite-return analysis for every declared function return type
- [X] Detect unreachable statements after unconditional returns
- [X] Detect duplicate variables, duplicate cases, and invalid shadowing uniformly
- [X] Complete expression precedence, unary operators, boolean operators, and
      short-circuit evaluation
- [X] Define integer overflow, numeric conversion, division, and comparison rules
- [X] Make tail-recursive calls compile to real BEAM tail calls
- [X] Define and implement exact semantics for `name;` once-only calls
- [X] Implement real semantics for `global`, `atomic`, `thread_local`, and
      `computed` instead of lowering them as ordinary locals
- [X] Add warnings separately from errors, including unused variables, unused
      parameters, shadowing, and ignored return values
- [ ] Preserve generated Erlang source maps so runtime failures point back to Terra
- [ ] Add deterministic compiler output and stable diagnostic codes for tools
- [ ] Add Zigs "try" keyword to make the function run because by default functions can fail in this langauge
- [ ] Add error propagation via the pipe operator "|>" if the pipe operator is used the error will get propagated via the program

## Milestone 2: Testing and Quality

- [ ] Create one command that builds and runs every test suite
- [ ] Add unit tests for every tokenizer, parser, type-checker, and codegen rule
- [ ] Add golden tests for generated Erlang source and diagnostics
- [ ] Add end-to-end tests that compile and run Terra programs on BEAM
- [ ] Add property-based tests for tokenization, parsing, and type checking
- [ ] Add parser fuzzing so malformed source never crashes the compiler
- [ ] Add differential tests comparing Terra behavior with generated Erlang
- [ ] Add recursion, mailbox, networking, and long-running soak tests
- [ ] Add benchmarks for compile time, generated-code speed, memory, and latency
- [ ] Run tests and static analysis in CI on supported Erlang/OTP versions

## Milestone 3: Resource Safety and Memory

Compile-time resource analysis should identify likely memory-growth problems,
but it must not claim that a program can never exhaust memory. Runtime inputs,
player counts, process creation, mailboxes, ETS tables, binaries, and external
code make total VM memory usage impossible to guarantee during transpilation.

- [ ] Add a warning-only `terra check --resources` analysis pass
- [ ] Detect non-tail recursion that can continuously grow the process stack
- [ ] Warn when processes are spawned from loops without a visible bound
- [ ] Warn about collections or state that grow inside unbounded loops/recursion
- [ ] Warn about actors that receive messages without overload or queue handling
- [ ] Detect large statically known literals, allocations, and repeated copies
- [ ] Warn when message shapes are likely to copy large values between processes
- [ ] Detect patterns that retain small references to unnecessarily large binaries
- [ ] Estimate statically knowable allocation sizes and explain uncertain estimates
- [ ] Give every resource diagnostic a source span, stable code, explanation, and fix
- [ ] Add opt-in resource annotations for process heap, mailbox, child-process, and
      outbound-queue budgets after Terra has stable actor/OTP support
- [ ] Lower process heap budgets to BEAM `max_heap_size` safeguards
- [ ] Generate supervisor behavior that contains and reports resource-limit failures
- [ ] Add runtime monitoring for process heaps, mailboxes, binaries, ETS, and VM memory
- [ ] Add configurable memory watermarks, admission control, and load shedding
- [ ] Document that VM-wide protection also requires OS/container memory limits
- [ ] Test resource diagnostics with golden tests and runtime limits with stress tests
- [ ] Measure false positives and keep uncertain findings as warnings, not errors

## Milestone 4: Modules and Erlang Interoperability

- [ ] Add Terra modules, imports, exports, and private functions
- [ ] Support separate compilation and incremental module builds
- [ ] Add an explicit Erlang FFI for calling modules and functions safely
- [ ] Allow Erlang code to call exported Terra functions
- [ ] Map Terra values predictably to Erlang terms
- [ ] Support Erlang records, maps, binaries, PIDs, references, and ports
- [ ] Generate OTP-compatible application metadata
- [ ] Integrate with `rebar3` projects and dependencies
- [ ] Add dependency locking and reproducible builds
- [ ] Detect module cycles and incompatible dependency versions

## Milestone 5: A Stronger Type System

- [ ] Add user-defined records/structs for game entities and messages
- [ ] Add enums and tagged unions for protocol and state-machine events
- [ ] Add exhaustive pattern matching over tuples, maps, lists, and tagged unions
- [ ] Add `Option` and `Result` types as a secondary fallback to nullable values
- [ ] Add type aliases for IDs, timestamps, and protocol fields
- [ ] Add function and callback types for reusable behavior
- [ ] Add bounded generics only where collections and APIs genuinely need them
- [ ] Add immutable update syntax for maps and records
- [ ] Add safe conversions between numeric and binary/string types
- [ ] Produce clear type traces showing where incompatible values originated

## Milestone 6: BEAM Concurrency and OTP

- [ ] Add lightweight process spawning
- [ ] Add typed message send and selective `receive`
- [ ] Add receive timeouts and mailbox pattern matching
- [ ] Expose process links, monitors, exits, and process aliases safely
- [ ] Add actor/server syntax or libraries that lower to `gen_server`
- [ ] Support supervisors and restart strategies
- [ ] Support OTP application start/stop lifecycle and supervision trees
- [ ] Add timer primitives based on monotonic time
- [ ] Add cancellation, task groups, and bounded worker pools
- [ ] Add mailbox size limits, overload detection, and backpressure helpers
- [ ] Add ETS wrappers for fast shared read-heavy state
- [ ] Add DETS/Mnesia adapters where durable or distributed state is appropriate
- [ ] Add distributed-node messaging, discovery, membership, and `pg` groups
- [ ] Document failure isolation and the "let it crash" model clearly

## Milestone 7: Networking for Game Servers

- [ ] Add TCP and UDP socket libraries
- [ ] Add TLS support with secure defaults
- [ ] Add HTTP client/server support
- [ ] Add WebSocket support for browser and realtime clients
- [ ] Add BEAM binary/bitstring syntax for efficient packet parsing
- [ ] Add framed-packet and streaming decoder APIs
- [ ] Add JSON support, followed by optional MessagePack/Protobuf libraries
- [ ] Add connection ownership, authentication, heartbeats, and idle timeouts
- [ ] Add bounded outbound queues and slow-client handling
- [ ] Add reconnect, resume-token, and session handoff helpers
- [ ] Add rate limiting and abuse protection
- [ ] Add protocol versioning and backward-compatible message decoding
- [ ] Add network simulation tests for latency, jitter, loss, and reordering

## Milestone 8: Game-Server Libraries and Examples

- [ ] Build a supervised player-session example
- [ ] Build lobby, room, and matchmaking libraries
- [ ] Build an authoritative game-room state machine
- [ ] Add fixed-rate tick scheduling with drift measurement
- [ ] Add input buffering, sequence numbers, and duplicate suppression
- [ ] Add state snapshots and delta-update helpers
- [ ] Add interest management for large worlds
- [ ] Add deterministic simulation and replay tooling
- [ ] Add persistence examples for player profiles and match results
- [ ] Add shard/zone ownership and migration examples
- [ ] Add graceful player reconnect and server-drain examples
- [ ] Add load bots and a multiplayer soak-test project
- [ ] Keep these as libraries/examples unless syntax provides a clear advantage

## Milestone 9: Standard Library

- [ ] Define a small, stable standard-library policy and naming convention
- [ ] Add `print`, formatting, and structured console APIs on top of `stdout`
- [ ] Add collection operations, iterators, sorting, and immutable transformations
- [ ] Add robust String and Binary APIs
- [ ] Add filesystem, path, environment, and process APIs
- [ ] Add time, duration, timer, random, UUID, hashing, and crypto wrappers
- [ ] Add error/result helpers and resource-safe cleanup
- [ ] Add configuration loading and validation
- [ ] Add HTTP, DNS, and database client interfaces
- [ ] Add a built-in testing/assertion library
- [ ] Document which Erlang/OTP standard modules Terra exposes directly

## Milestone 10: Developer Experience

- [ ] Add `terra new`, project manifests, and standard project layout
- [ ] Add a canonical formatter with `terra fmt` and `terra fmt --check`
- [ ] Add a REPL that compiles snippets through the normal compiler pipeline
- [ ] Add a language server with diagnostics, hover types, completion, rename,
      references, and go-to-definition
- [ ] Add syntax highlighting and editor integrations
- [ ] Add generated API documentation and runnable documentation tests
- [ ] Add `terra test`, filtering, watch mode, and coverage reporting
- [ ] Add `terra check --watch` with incremental recompilation
- [ ] Add a debugger story using BEAM tracing and source maps
- [ ] Make `terra explain` show call graphs, inferred types, and process topology
- [ ] Improve errors with related locations, such as both sides of a duplicate
      declaration or the function signature behind a bad call

## Milestone 11: Operations and Production Readiness

- [ ] Add structured logging with request/player/match correlation IDs
- [ ] Add metrics, tracing, and OpenTelemetry integration
- [ ] Add health, readiness, and overload endpoints
- [ ] Add crash reports that map generated Erlang frames back to Terra source
- [ ] Add release builds, configuration, and secret handling
- [ ] Add graceful shutdown, connection draining, and rolling restart support
- [ ] Investigate BEAM hot-code upgrades after ordinary releases are reliable
- [ ] Add profiling workflows for scheduler usage, reductions, memory, and mailboxes
- [ ] Add memory limits and safeguards against unbounded queues/collections
- [ ] Add secure defaults for TLS, deserialization, filesystem, and shell access
- [ ] Add dependency auditing and reproducible release artifacts
- [ ] Publish compatibility guarantees and a language-version migration policy

## Milestone 12: General-Purpose Programming

- [ ] Build polished CLI-application support
- [ ] Add file streaming and data-processing examples
- [ ] Add HTTP services, background jobs, and scheduled-task examples
- [ ] Add database migrations, transactions, and connection pooling libraries
- [ ] Add process execution and port integration with explicit safety boundaries
- [ ] Add package publishing, package documentation, and dependency discovery
- [ ] Add cross-platform release testing for Linux, macOS, and Windows
- [ ] Provide escape hatches to Erlang without weakening Terra's safety guarantees

## Suggested Implementation Order

1. Source spans, compiler passes, complete AST, and semantic correctness
2. Test runner, fuzzing, golden tests, and CI
3. Warning-only resource analysis for recursion, allocation, and bounded growth
4. Modules, Erlang FFI, separate compilation, and `rebar3` integration
5. Records/tagged unions, pattern matching, `Option`, and `Result`
6. Processes, messages, supervisors, OTP applications, and ETS
7. Enforceable process budgets, memory monitoring, and overload protection
8. Binary protocols, TCP/UDP/TLS, HTTP, and WebSockets
9. Session, room, matchmaking, tick, snapshot, and load-test libraries
10. Formatter, LSP, REPL, debugger, package workflow, and documentation
11. Observability, releases, profiling, security, and operational hardening

The first serious game-server milestone should be a supervised TCP/WebSocket
server with typed messages, one process per session, room processes, ETS-backed
lookup state, reconnect handling, metrics, and a reproducible load test.
