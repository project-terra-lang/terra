# OTP Integration Policy

Terra integrates with Erlang/OTP through libraries by default. Existing Terra
modules, checked `extern` declarations, and Erlang-facing `export` wrappers are
the preferred boundary for OTP modules and behaviors.

## Default Route

Use the smallest existing mechanism that fits:

1. Call an OTP function through an explicit, typed `extern` declaration.
2. Put repeated interop details behind an ordinary Terra module and export only
   the operations callers need.
3. Use a small Erlang adapter module when an OTP behavior requires callbacks or
   return shapes that Terra cannot express directly yet.

This keeps supervisors, applications, releases, links, monitors, registries,
timeouts, and behavior-specific lifecycle rules in OTP itself. Terra does not
duplicate those systems.

## When Syntax Is Earned

New OTP-specific syntax should be considered only when all of these are true:

- Real programs repeat the same integration pattern often enough that a library
  or adapter remains awkward.
- The compiler can provide a useful static guarantee that a function wrapper
  cannot provide.
- The construct has clear process, failure, and temporary-region semantics.
- It lowers predictably to ordinary Erlang/OTP APIs without creating a parallel
  runtime framework.
- A small example and focused regression tests can explain its complete behavior.

Syntax is not justified only to shorten an OTP function call or mirror an Erlang
behavior name. Until the criteria above are met, OTP integration remains
library-first.

## Current Boundary

Terra's built-in `self`, `spawn`, `send`, and typed `receive` operations are the
small process foundation. They do not replace OTP supervision or behaviors.
Temporary pointers cannot cross process or FFI boundaries. Terra values crossing
those boundaries continue to use the documented Erlang term mapping.

See `examples/otp_library_first.terra` for a checked call to the OTP `filename`
module without adding language syntax.
