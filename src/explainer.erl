-module(explainer).
-export([format/1]).

format(#{entry := Entry, functions := Functions}) ->
    ["Terra program\n",
     io_lib:format("  Entry point: ~s\n", [Entry]),
     io_lib:format("  Functions: ~p\n", [length(Functions)]),
     [format_function(Function) || Function <- Functions]].

format_function(Function) ->
    Name = maps:get(name, Function),
    ["\n", signature(Function), "\n",
     format_statements(maps:get(statements, Function, []), Name, 1)].

signature(#{name := Name, params := Params, return_types := Returns}) ->
    ["function ", format_return_types(Returns), " ", Name, "(",
     lists:join(", ", [[type_name(maps:get(type, Param)), " ", maps:get(name, Param)]
                        || Param <- Params]), ")"].

format_return_types([Type]) -> type_name(Type);
format_return_types(Types) ->
    ["(", lists:join(", ", [type_name(Type) || Type <- Types]), ")"].

format_statements([], _FunctionName, Indent) ->
    [spaces(Indent), "- no executable statements\n"];
format_statements(Statements, FunctionName, Indent) ->
    [format_statement(Statement, FunctionName, Indent) || Statement <- Statements].

format_statement(#{kind := call, name := stdout}, _FunctionName, Indent) ->
    [spaces(Indent), "- writes a value to the console with stdout\n"];
format_statement(#{kind := call, name := Name, invocation := Invocation},
                 FunctionName, Indent) ->
    Recursive = case display_name(Name) == FunctionName of
                    true -> ", recursive";
                    false -> ""
                end,
    [spaces(Indent), "- calls ", display_name(Name), " ",
     invocation(Invocation), Recursive, "\n"];
format_statement(#{kind := return, values := Values}, _FunctionName, Indent) ->
    Count = length(Values),
    [spaces(Indent), io_lib:format("- returns ~p ~s\n", [Count, plural(Count, "value")])];
format_statement(#{kind := multi_binding, bindings := Bindings}, _FunctionName, Indent) ->
    Names = [maps:get(name, Binding) || Binding <- Bindings],
    [spaces(Indent), "- assigns multiple results to ", lists:join(", ", Names), "\n"];
format_statement(#{kind := variable, name := Name, type := Type}, _FunctionName, Indent) ->
    [spaces(Indent), "- declares ", type_name(Type), " ", Name, "\n"];
format_statement(#{kind := 'if', branches := Branches, else_branch := Else},
                 FunctionName, Indent) ->
    Count = length(Branches),
    [spaces(Indent), io_lib:format("- if chain with ~p ~s~s\n",
                                  [Count, plural(Count, "condition"), else_text(Else)]),
     [format_statements(maps:get(statements, Branch), FunctionName, Indent + 1)
      || Branch <- Branches],
     format_optional_statements(Else, FunctionName, Indent + 1)];
format_statement(#{kind := unless, statements := Statements, else_branch := Else},
                 FunctionName, Indent) ->
    [spaces(Indent), "- unless condition", else_text(Else), "\n",
     format_statements(Statements, FunctionName, Indent + 1),
     format_optional_statements(Else, FunctionName, Indent + 1)];
format_statement(#{kind := switch, cases := Cases}, FunctionName, Indent) ->
    [spaces(Indent), io_lib:format("- exhaustive switch with ~p case(s); breaks by default\n",
                                  [length(Cases)]),
     [format_statements(maps:get(statements, Case), FunctionName, Indent + 1)
      || Case <- Cases]];
format_statement(#{kind := for_each, binding := Binding, statements := Statements},
                 FunctionName, Indent) ->
    [spaces(Indent), "- for_each binds ", Binding, " and implicit it\n",
     format_statements(Statements, FunctionName, Indent + 1)];
format_statement(#{kind := 'for', statements := Statements}, FunctionName, Indent) ->
    [spaces(Indent), "- range loop with implicit it\n",
     format_statements(Statements, FunctionName, Indent + 1)];
format_statement(#{kind := Kind, statements := Statements}, FunctionName, Indent)
  when Kind == while; Kind == do_while ->
    [spaces(Indent), "- ", atom_to_list(Kind), " loop with implicit it\n",
     format_statements(Statements, FunctionName, Indent + 1)];
format_statement(_Statement, _FunctionName, Indent) ->
    [spaces(Indent), "- statement\n"].

format_optional_statements(none, _FunctionName, _Indent) -> [];
format_optional_statements(Statements, FunctionName, Indent) ->
    format_statements(Statements, FunctionName, Indent).

else_text(none) -> " and no else branch";
else_text(_Else) -> " and an else branch".

invocation(once) -> "once";
invocation(repeated) -> "normally".

display_name(Name) when is_atom(Name) -> atom_to_list(Name);
display_name(Name) -> Name.

spaces(Indent) -> lists:duplicate(Indent * 2, $\s).

plural(1, Word) -> Word;
plural(_Count, Word) -> Word ++ "s".

type_name(number) -> "Number";
type_name(int) -> "Int";
type_name(sint) -> "SInt";
type_name(float) -> "Float";
type_name(atom) -> "Atom";
type_name(bool) -> "Bool";
type_name(map) -> "Map";
type_name(list) -> "List";
type_name(tuple) -> "Tuple";
type_name(string) -> "String";
type_name(var) -> "Var";
type_name(Type) -> atom_to_list(Type).
