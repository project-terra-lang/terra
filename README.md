# A Simple Programming Language Project
- [ ] (Concurrent Programming Langauge)
- [ ] (Immutable State Machine, Support for Fake Mutability via a new mechanism)
- [ ] (Turing Complete)
- [ ] (Small Standard Library)

> ADD MORE FEATURES OVER TIME AS THIS IS A RESEARCH PROJECT <br>
> This Language will be a transpiler (basically converting our source code to beam source files to be run in erlang runtime)

1. Variables
- All Variables are Immutable
```lua
-- global variables
global State state = State{};

-- local variables
local Int x = 10;
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
if x < 69420 {
    print("Hallo");
} elseif x < 100 {
    print('c');
} else {
    print(100);
}

unless x < 69420 {
    print("Hallo");
} else {
    print(100);
}
```
