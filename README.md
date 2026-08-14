# A Simple Programming Language Project
- [ ] (Concurrent Programming Langauge)
- [ ] (Immutable State Machine, Support for Fake Mutability via a new mechanism)
- [ ] (Turing Complete)
- [ ] (Small Standard Library)

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

Tuple

Map
RestrictedMap -- this is the same as a map but we can set the length of it

List

String (Super Data Type)
    BinaryString
    CharList
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
```lua
function x() : (Int, String) {
    return 69420, "nice";
}

function x(Int x) : (Int, String) {
    return x, "nice";
}
```

3. Condition Handling
```elixir
# if..elseif..else
if x < 69420 {
    print("Hallo");
} elseif x < 100 {
    print('c');
} else {
    print(100);
}

# unless..else
unless x < 69420 {
    print("Hallo");
} else {
    print(100);
}

# switch statement
# - break by default
# - pattern matching
# - exhaustive
if x == {
    case 69420:
        print();

    case:
        whatever();
}
```

4. Loops
```lua
for_each x in y {
    -- implicit variable called it is stored in every iterable sequence
    print(x.it.whatever);
}

for range(10) {
    print(it);
}

while true {
    print(it);
}

do_while true {
    print(it)
}
``` 
