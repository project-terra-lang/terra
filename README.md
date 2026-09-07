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
```

Integers use BEAM arbitrary-precision arithmetic, so integer operations do not
overflow. Mixed numeric arithmetic promotes to `Float`, then `SInt`, then
`Int`; same-type integer arithmetic preserves its type, and `/` always produces
`Float`. Numeric constructors provide explicit conversions.

1. Variables
- All Variables are Immutable
```lua
-- global variables
global State state = State();

-- local variables
local Int x = 10;

-- temporary variables
temp Var zss = Var();
```

`global` values are initialized successfully once and shared by all BEAM
processes running the generated module. `thread_local` values initialize once
per BEAM process. `atomic` stores `Int` or `SInt` values in a BEAM atomic cell,
and `computed` reevaluates its expression whenever the binding is read.

`RestrictedMap(capacity, map)` creates an immutable map whose initial member
count cannot exceed its non-negative integer capacity; `RestrictedMap(capacity)`
creates an empty bounded map. Both `Map` and `RestrictedMap` expose `.count`
for their member count and `.members` for a list of key/value tuples.

2. Functions
- Functions support multiple Return Values
- Functions support tail-call optimization
- Functions must always declare a concrete return type and return a value.
- Terra has no `void` functions.
- `name();` invokes a function normally and can run it multiple times.
- `try name();` invokes a user function with explicit failure propagation:
  successful values are unchanged, while failures retain their BEAM reason and
  Terra stack. Bare calls remain valid in language version 0.
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
