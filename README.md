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
List
Tuple

String
```

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

2. Functions
- Functions support multiple Return Values
- Functions support tail-call optimization
- `name();` invokes a function normally and can run it multiple times.
- `name;` marks a once-only invocation for the runtime/code-generation stage.
- Terra programs run through one fixed entry point:
```lua
function Number Main(String Args) {
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
- `for_each` accepts `List`, `Tuple`, `Map`, and `String` values.
- Loop bodies receive an implicit `it` variable.
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
