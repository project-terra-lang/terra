# Tooling Policy

Terra's editor and tooling surface should stay deliberately small while the
language remains a research project. Tooling exists to keep examples, tests, and
compiler behavior easy to inspect; it should not force the compiler into a
stable-product shape before the language earns one.

## Supported Now

The maintained tooling surface is:

- `./build.sh --build` to compile the Erlang implementation modules.
- `./build.sh --test` to run every checked-in test suite.
- `./run.sh check <file.terra>` for diagnostics.
- `./run.sh explain <file.terra>` for checked type and control-flow summaries.
- `./run.sh fmt <file.terra>` and `./run.sh fmt --check <file.terra>` for the
  current canonical formatter.
- `./run.sh emit <file.terra>` for inspecting generated Erlang.
- Minimal VS Code shell tasks that invoke the commands above without adding a
  separate extension, language server, debugger, or custom protocol.

This is enough for the current project rhythm: edit a small feature, check or
explain one file, run the full suite, and inspect generated Erlang when needed.

## Deferred Until The Language Settles

Do not add these as active Milestone 5 work:

- A full language server.
- Autocomplete or semantic highlighting protocols.
- A debugger, profiler, package manager, or project generator.
- Editor-specific syntax grammars that need constant churn with the parser.
- Build-system integrations beyond tiny wrappers around `build.sh` and
  `run.sh`.

These ideas can move out of the parked area later when Terra's syntax,
diagnostics, imports, standard library, and BEAM integration are stable enough
that editor features would not be rewritten every few milestones.

## Admission Rule

Add tooling only when it directly supports the existing research loop and can be
implemented as a thin wrapper over maintained compiler commands. If a tool needs
new compiler protocols, background daemons, broad editor APIs, or long-lived
state, keep it parked and document the missing compiler guarantees instead.
