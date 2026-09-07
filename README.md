# A Simple Programming Language Project
- [ ] (Concurrent Programming Langauge)
- [ ] (Immutable State Machine, Support for Fake Mutability via a new mechanism)
- [ ] (Turing Complete)
- [ ] (Small Standard Library)
- [ ] (An Imperative Programming Language that has features of erlang)

** Just Make this a simple Language no need any complete features 
** Its just a research project anyways

> ADD MORE FEATURES OVER TIME AS THIS IS A RESEARCH PROJECT <br>
> This Language will be a transpiler (basically converting our source code to beam source files to be run in erlang runtime) <br>
> Design the language in a way in which it will work nicely with the erlang ecosystem and that it has a nice imperative syntax for people to code there game servers

0. Data Types
```elixir
Number (Super Data Type)
    - Int
    - SInt 
    - Float

Atom

Bool

Map
RestrictedMap
List
Tuple

String

User-defined structs and tagged enums
```

Integers use BEAM arbitrary-precision arithmetic, so integer operations do not
overflow. `SInt` can accept ordinary integer values because it is a source-level
signed intent, not a separate runtime range. Mixed numeric arithmetic promotes
to `Float`, then `SInt`, then `Int`; same-type integer arithmetic preserves its
type, and `/` always produces `Float`. Numeric constructors provide explicit
conversions.

1. Variables
- All Variables are Immutable
```lua
-- module-scope global variables
global State state = State();

-- module-scope compile-time constants
const Int max_players = 128;

-- local variables
local Int x = 10;

-- temporary variables
temp Var zss = Var();
```

`global` values may be written at module scope, outside any function body. They
are initialized successfully once and shared by all BEAM processes running the
generated module. `const` values may also be written at module scope; because
they are compile-time constants, they are resolved before globals and ordinary
function bindings. All other variable declarations must be written inside a
function or block scope. `thread_local` values initialize once per BEAM
process. `atomic` stores `Int` or `SInt` values in a BEAM atomic cell, and
`computed` reevaluates its expression whenever the binding is read.

`RestrictedMap(capacity, map)` creates an immutable map whose initial member
count cannot exceed its non-negative integer capacity; `RestrictedMap(capacity)`
creates an empty bounded map. Both `Map` and `RestrictedMap` expose `.count`
for their member count and `.members` for a list of key/value tuples.

Plain immutable data can be defined with a module-level struct and constructed
positionally in field order:
```lua
struct Player {
    String name;
    Int score;
}

local Player player = Player("Ada", 7);
stdout(player.name);
```

Struct constructors and field access are statically checked. Struct values map
directly to tagged BEAM maps and may be used in function parameters and returns.

Tagged enums model small state machines and result values:
```lua
enum Result {
    variant Ok(Int value);
    variant Error(String message);
    variant Pending;
}

local Result result = Result.Ok(7);
stdout(result.tag);  -- :Ok
```

Each `variant` line is an explicit data-constructor declaration. For example,
`variant Ok(Int value);` declares the tag `:Ok`, payload field `value`, and the
constructor signature `Result.Ok(Int) -> Result`. Constructors only package
immutable data; custom validation or other behavior belongs in an ordinary user
function. Every enum value exposes its variant as the `.tag` Atom, and variant
payloads use their declared field names.

Switches can match enum variants and bind payloads explicitly:
```lua
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

`bind name` creates an immutable binding scoped to that case. `_` ignores a
payload field. Pattern matching is intentionally limited to enum cases where it
replaces manual tag checks and unsafe payload access.

2. Functions
- Functions support multiple Return Values
- Functions support tail-call optimization
- Functions must always declare a concrete return type and return a value.
- Terra has no `void` functions.
- `name();` invokes a function normally and can run it multiple times.
- `try name();` invokes a user function with explicit failure propagation:
  successful values are unchanged, while failures retain their BEAM reason and
  Terra stack. Bare calls remain valid in language version 0.
- `value |> Next(extra)` passes `value` as the first argument to `Next`, chains
  left-to-right, and propagates failures with the same reason and Terra stack as
  `try`.
- `name;` invokes a zero-argument function successfully at most once per
  generated module and BEAM process; `name()` always invokes normally.
- Terra programs run through one fixed entry point:
```lua
function Number Main(String Args) {
    return 0;
}
```

```lua
function (Int, String)  x(){
    return 69420, "nice";
}

function (Int, String) x(Int x) {
    return x, "nice";
}
```

Multiple returned values can be assigned to typed local variables:
```lua
function (String, Number) T() {
    return "", 69420;
}

function Number Main(String Args) {
    local String x, Number y = T();
    return y;
}
```

3. Condition Handling
- Conditions must evaluate to `Bool`.
- Conditions support unary `!`, comparison operators, and short-circuiting
  `&&` / `||` boolean operators.
- Switch cases break by default and must include a final default `case:`.
```elixir
# if..elseif..else
if x < 69420 {
    stdout("Hallo");
} elseif x < 100 {
    stdout('c');
} else {
    stdout(100);
}

# unless..else
unless x < 69420 {
    stdout("Hallo");
} else {
    stdout(100);
}

# switch statement
# - break by default
# - pattern matching
# - exhaustive
if x == {
    case 69420:
        stdout();

    case:
        whatever();
}
```

4. Loops
- `for_each` accepts `List`, `Tuple`, `Map`, `RestrictedMap`, and `String` values.
- Loop conditions and bodies receive an implicit `it` counter variable.
- Recursive calls use the normal function-call syntax and are type checked.
```lua
for_each x in y {
    -- implicit variable called it is stored in every iterable sequence
    stdout(x.it.whatever);
}

for range(10) {
    stdout(it);
}

while true {
    stdout(it);
}

do_while true {
    stdout(it)
}
``` 

`stdout(...)` is the built-in console output operation. `print(...)` is left
available for a future standard-library function.

5. Developer Feedback
- `terra check file.terra` reports a stable error code, a plain-language
  explanation, and a suggested fix.
- Diagnostic codes are lower-snake-case identifiers shown in brackets, such as
  `[missing_return]`; tools may rely on the code even when wording changes.
- Successful checks report non-failing warnings for unused variables,
  unused parameters, shadowing, and ignored function return values.
- `terra explain file.terra` prints a readable walkthrough of functions,
  control flow, loops, calls, recursion, and returns.
- `terra ast file.terra` remains available for inspecting the compiler AST.

6. Erlang and BEAM Backend
- `terra emit file.terra` writes generated Erlang source to `terra_build/`.
- `terra build file.terra` generates Erlang and compiles a `.beam` module.
- `terra run file.terra [args...]` builds the module and runs Terra `Main` on
  the BEAM VM.
- Generated BEAM debug metadata preserves Terra source paths and function
  locations so runtime diagnostics show Terra code frames.
- Repeated compilation of the same source path produces byte-identical Erlang
  source and deterministic BEAM output.
- `TERRA_BUILD_DIR` can override the default `terra_build/` output directory.
- Terra multiple returns compile to Erlang tuples, immutable locals compile to
  Erlang single-assignment variables, and calls returned directly from a
  function compile through a constant-stack BEAM tail-call dispatch loop.

Try the complete feature showcase:
```bash
./build.sh --build
./run.sh explain examples/feature_showcase.terra
./run.sh emit examples/feature_showcase.terra
./run.sh run examples/feature_showcase.terra hello from terra
```

Or run the smaller tail-recursive counter example:
```bash
./run.sh run examples/counter.terra
```
