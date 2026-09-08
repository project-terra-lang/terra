-module(explainer).
-export([format/1]).

format(#{entry := Entry, functions := Functions} = Program) ->
    Context = #{functions => function_returns(Functions),
                module_env => declaration_env(maps:get(module_declarations, Program, []))},
    ["Terra program\n",
     io_lib:format("  Entry point: ~s\n", [Entry]),
     io_lib:format("  Functions: ~p\n", [length(Functions)]),
     [format_function(Function, Context) || Function <- Functions]].

function_returns(Functions) ->
    maps:from_list([{maps:get(name, Function), maps:get(return_types, Function, [])}
                    || Function <- Functions]).

declaration_env(Declarations) ->
    maps:from_list([{maps:get(name, Declaration), maps:get(type, Declaration)}
                    || Declaration <- Declarations]).

format_function(Function, Context) ->
    Name = maps:get(name, Function),
    Env = maps:merge(maps:get(module_env, Context, #{}),
                     maps:from_list([{maps:get(name, Param), maps:get(type, Param)}
                                     || Param <- maps:get(params, Function, [])])),
    ["\n", signature(Function), "\n",
     format_statements(maps:get(statements, Function, []), Name, 1, Env, Context)].

signature(#{name := Name, params := Params, return_types := Returns}) ->
    ["function ", format_return_types(Returns), " ", Name, "(",
     lists:join(", ", [[type_name(maps:get(type, Param)), " ", maps:get(name, Param)]
                        || Param <- Params]), ")"].

format_return_types([Type]) -> type_name(Type);
format_return_types(Types) ->
    ["(", lists:join(", ", [type_name(Type) || Type <- Types]), ")"].

format_statements([], _FunctionName, Indent, _Env, _Context) ->
    [spaces(Indent), "- no executable statements\n"];
format_statements(Statements, FunctionName, Indent, Env, Context) ->
    {Lines, _FinalEnv} =
        lists:foldl(
          fun(Statement, {Acc, CurrentEnv}) ->
                  {Line, NextEnv} =
                      format_statement(Statement, FunctionName, Indent, CurrentEnv, Context),
                  {[Acc, Line], NextEnv}
          end,
          {[], Env},
          Statements),
    Lines.

format_statement(#{kind := call, name := stdout}, _FunctionName, Indent, Env, _Context) ->
    {[spaces(Indent), "- writes values to stdout and returns Atom\n"], Env};
format_statement(#{kind := call, name := Name}, _FunctionName, Indent, Env, _Context)
  when Name == "print"; Name == "println"; Name == "eprint"; Name == "eprintln" ->
    {[spaces(Indent), "- writes formatted values with ", Name, " and returns Atom\n"], Env};
format_statement(#{kind := call, name := Name, args := Args,
                   invocation := Invocation} = Statement,
                 FunctionName, Indent, Env, Context) ->
    Recursive = case display_name(Name) == FunctionName of
                    true -> ", recursive";
                    false -> ""
                end,
    Propagation = case maps:get(propagation, Statement, normal) of
                      'try' -> " with explicit try propagation";
                      normal -> ""
                  end,
    Types = call_return_types(Name, Args, Env, Context),
    {[spaces(Indent), "- calls ", display_name(Name), " ",
      invocation(Invocation), Propagation, Recursive,
      " -> ", format_type_list(Types), "\n"], Env};
format_statement(#{kind := pointer_write, pointer := Pointer, value := Value}, _FunctionName,
                 Indent, Env, Context) ->
    PointerType = expression_type(Pointer, Env, Context),
    ValueType = expression_type(Value, Env, Context),
    {[spaces(Indent), "- writes ", type_name(ValueType), " into ",
      type_name(PointerType), " pointer storage\n"], Env};
format_statement(#{kind := return, values := [{pipe_call, _, _, _} = Pipeline]},
                 _FunctionName, Indent, Env, Context) ->
    Types = [expression_type(Pipeline, Env, Context)],
    {[spaces(Indent), io_lib:format("- returns a ~p-stage propagating pipeline -> ",
                                   [pipe_stages(Pipeline)]),
      format_type_list(Types), "\n"], Env};
format_statement(#{kind := return, values := Values}, _FunctionName, Indent, Env, Context) ->
    Types = [expression_type(Value, Env, Context) || Value <- Values],
    Count = length(Values),
    {[spaces(Indent), io_lib:format("- returns ~p ~s -> ",
                                   [Count, plural(Count, "value")]),
      format_type_list(Types), "\n"], Env};
format_statement(#{kind := multi_binding, bindings := Bindings, value := Value},
                 _FunctionName, Indent, Env, Context) ->
    SourceType = expression_type(Value, Env, Context),
    NextEnv = bind_all(Bindings, Env),
    {[spaces(Indent), "- destructures ", type_name(SourceType), " into ",
      lists:join(", ", [maps:get(name, Binding) ++ ": " ++
                        flatten_type(maps:get(type, Binding))
                        || Binding <- Bindings]), "\n"],
     NextEnv};
format_statement(#{kind := variable, name := Name, type := Type, value := Value,
                   scope := Scope, eval := Eval, concurrency := Concurrency},
                 _FunctionName, Indent, Env, Context) ->
    ValueType = expression_type(Value, Env, Context),
    NextEnv = maps:put(Name, Type, Env),
    {[spaces(Indent), "- declares ", binding_prefix(Scope, Eval, Concurrency),
      type_name(Type), " ", Name, " from ", expression_kind(Value),
      " -> ", type_name(ValueType), "\n"], NextEnv};
format_statement(#{kind := 'if', branches := Branches, else_branch := Else},
                 FunctionName, Indent, Env, Context) ->
    Count = length(Branches),
    {[spaces(Indent), io_lib:format("- if chain with ~p ~s~s; ~s\n",
                                   [Count, plural(Count, "condition"),
                                    else_text(Else), flow_note(Branches, Else)]),
      [format_branch(Branch, FunctionName, Indent + 1, Env, Context)
       || Branch <- Branches],
      format_optional_statements(Else, FunctionName, Indent + 1, Env, Context)],
     Env};
format_statement(#{kind := unless, condition := Condition, statements := Statements,
                   else_branch := Else},
                 FunctionName, Indent, Env, Context) ->
    {[spaces(Indent), "- unless condition is ",
      type_name(expression_type(Condition, Env, Context)), else_text(Else),
      "; ", flow_note([#{statements => Statements}], Else), "\n",
      format_statements(Statements, FunctionName, Indent + 1, Env, Context),
      format_optional_statements(Else, FunctionName, Indent + 1, Env, Context)],
     Env};
format_statement(#{kind := switch, subject := Subject, cases := Cases} = Statement,
                 FunctionName, Indent, Env, Context) ->
    Exhaustive = maps:get(exhaustive, Statement, true),
    {[spaces(Indent), io_lib:format("- exhaustive switch on ~s with ~p case(s); ~s\n",
                                   [type_name(expression_type(Subject, Env, Context)),
                                    length(Cases), switch_flow_note(Cases, Exhaustive)]),
      [format_case(Case, FunctionName, Indent + 1, Env, Context) || Case <- Cases]],
     Env};
format_statement(#{kind := for_each, binding := Binding, iterable := Iterable,
                   statements := Statements},
                 FunctionName, Indent, Env, Context) ->
    LoopEnv = maps:put("it", int, maps:put(Binding, var, Env)),
    {[spaces(Indent), "- for_each iterates ", type_name(expression_type(Iterable, Env, Context)),
      "; binds ", Binding, " and implicit it: Int in the loop only\n",
      format_statements(Statements, FunctionName, Indent + 1, LoopEnv, Context)],
     Env};
format_statement(#{kind := 'for', iterator := Iterator, statements := Statements},
                 FunctionName, Indent, Env, Context) ->
    LoopEnv = maps:put("it", int, Env),
    {[spaces(Indent), "- range loop over ", type_name(expression_type(Iterator, Env, Context)),
      "; implicit it: Int stays loop-local\n",
      format_statements(Statements, FunctionName, Indent + 1, LoopEnv, Context)],
     Env};
format_statement(#{kind := Kind, condition := Condition, statements := Statements},
                 FunctionName, Indent, Env, Context)
  when Kind == while; Kind == do_while ->
    LoopEnv = maps:put("it", int, Env),
    {[spaces(Indent), "- ", atom_to_list(Kind), " loop condition is ",
      type_name(expression_type(Condition, Env, Context)),
      "; implicit it: Int stays loop-local and the loop may repeat\n",
      format_statements(Statements, FunctionName, Indent + 1, LoopEnv, Context)],
     Env};
format_statement(_Statement, _FunctionName, Indent, Env, _Context) ->
    {[spaces(Indent), "- statement\n"], Env}.

format_branch(Branch, FunctionName, Indent, Env, Context) ->
    Condition = maps:get(condition, Branch),
    [spaces(Indent), "- condition is ", type_name(expression_type(Condition, Env, Context)),
     "\n",
     format_statements(maps:get(statements, Branch), FunctionName, Indent + 1, Env, Context)].

format_case(#{pattern := Pattern, statements := Statements}, FunctionName, Indent, Env, Context) ->
    CaseEnv = pattern_env(Pattern, Env),
    [spaces(Indent), "- case ", pattern_text(Pattern), "\n",
     format_statements(Statements, FunctionName, Indent + 1, CaseEnv, Context)].

pattern_env({variant_pattern, _EnumName, _VariantName, Bindings}, Env) ->
    lists:foldl(
      fun(#{binding := "_"}, Acc) -> Acc;
         (#{binding := Name, type := Type}, Acc) -> maps:put(Name, Type, Acc)
      end,
      Env,
      Bindings);
pattern_env(_Pattern, Env) ->
    Env.

pattern_text(default) ->
    "default";
pattern_text({variant_pattern, EnumName, VariantName, Bindings}) ->
    [EnumName, ".", VariantName, "(",
     lists:join(", ", [pattern_binding_text(Binding) || Binding <- Bindings]), ")"];
pattern_text(Pattern) ->
    [expression_kind(Pattern), " pattern"].

pattern_binding_text(#{binding := "_"}) -> "_";
pattern_binding_text(#{binding := Name, type := Type}) -> [Name, ": ", type_name(Type)].

format_optional_statements(none, _FunctionName, _Indent, _Env, _Context) -> [];
format_optional_statements(Statements, FunctionName, Indent, Env, Context) ->
    format_statements(Statements, FunctionName, Indent, Env, Context).

flow_note(Branches, none) ->
    case all_statement_lists_return([maps:get(statements, Branch) || Branch <- Branches]) of
        true -> "matching branch returns, otherwise control continues";
        false -> "control may continue after the branch"
    end;
flow_note(Branches, Else) ->
    Lists = [maps:get(statements, Branch) || Branch <- Branches] ++ [Else],
    case all_statement_lists_return(Lists) of
        true -> "all paths return";
        false -> "some paths continue after the branch"
    end.

switch_flow_note(Cases, true) ->
    case all_statement_lists_return([maps:get(statements, Case) || Case <- Cases]) of
        true -> "all cases return";
        false -> "matched case runs and control may continue"
    end;
switch_flow_note(_Cases, false) ->
    "non-exhaustive switch may continue".

all_statement_lists_return(Lists) ->
    lists:all(fun statements_return/1, Lists).

statements_return([]) ->
    false;
statements_return(Statements) ->
    lists:any(fun statement_returns/1, Statements).

statement_returns(#{kind := return}) ->
    true;
statement_returns(#{kind := 'if', branches := Branches, else_branch := Else}) ->
    Else =/= none andalso
    all_statement_lists_return([maps:get(statements, Branch) || Branch <- Branches] ++ [Else]);
statement_returns(#{kind := switch, cases := Cases, exhaustive := true}) ->
    all_statement_lists_return([maps:get(statements, Case) || Case <- Cases]);
statement_returns(_) ->
    false.

bind_all(Bindings, Env) ->
    lists:foldl(fun(Binding, Acc) ->
                        maps:put(maps:get(name, Binding), maps:get(type, Binding), Acc)
                end,
                Env,
                Bindings).

binding_prefix(local, runtime, shared) -> "";
binding_prefix(Scope, Eval, Concurrency) ->
    Words = unique_words(scope_words(Scope) ++ eval_words(Eval) ++ concurrency_words(Concurrency),
                         []),
    case Words of
        [] -> "";
        _ -> [lists:join(" ", Words), " "]
    end.

scope_words(local) -> [];
scope_words(Scope) -> [atom_to_list(Scope)].

eval_words(runtime) -> [];
eval_words(Eval) -> [atom_to_list(Eval)].

concurrency_words(shared) -> [];
concurrency_words(Concurrency) -> [atom_to_list(Concurrency)].

unique_words([], Acc) ->
    lists:reverse(Acc);
unique_words([Word | Rest], Acc) ->
    case lists:member(Word, Acc) of
        true -> unique_words(Rest, Acc);
        false -> unique_words(Rest, [Word | Acc])
    end.

expression_type({int, _Value}, _Env, _Context) -> int;
expression_type({sint, _Value}, _Env, _Context) -> sint;
expression_type({float, _Value}, _Env, _Context) -> float;
expression_type({string, _Value}, _Env, _Context) -> string;
expression_type({char, _Value}, _Env, _Context) -> int;
expression_type({bool, _Value}, _Env, _Context) -> bool;
expression_type({atom, _Value}, _Env, _Context) -> atom;
expression_type({list, _Values}, _Env, _Context) -> list;
expression_type({tuple, _Values}, _Env, _Context) -> tuple;
expression_type({map, _Pairs}, _Env, _Context) -> map;
expression_type({record, Name, _Fields}, _Env, _Context) -> {named, Name};
expression_type({variant, EnumName, _VariantName, _Fields}, _Env, _Context) -> {named, EnumName};
expression_type({update, Base, _Updates}, Env, Context) -> expression_type(Base, Env, Context);
expression_type({pointer_new, Value}, Env, Context) ->
    {pointer, expression_type(Value, Env, Context)};
expression_type({pointer_read, Value}, Env, Context) ->
    case expression_type(Value, Env, Context) of
        {pointer, Type} -> Type;
        {strict_pointer, Type} -> Type;
        _Other -> unknown
    end;
expression_type({var_ref, Name}, Env, _Context) ->
    maps:get(Name, Env, unknown);
expression_type({member, Value, Name}, Env, Context) ->
    member_type(expression_type(Value, Env, Context), Name);
expression_type({unary, bang, _Value}, _Env, _Context) -> bool;
expression_type({unary, minus, Value}, Env, Context) -> expression_type(Value, Env, Context);
expression_type({binary, Op, Left, Right}, Env, Context) ->
    binary_type(Op, expression_type(Left, Env, Context), expression_type(Right, Env, Context));
expression_type({try_call, Name, Args}, Env, Context) ->
    single_return(call_return_types(Name, Args, Env, Context));
expression_type({pipe_call, Left, Name, Args}, Env, Context) ->
    PipeEnv = maps:put("$pipe", expression_type(Left, Env, Context), Env),
    single_return(call_return_types(Name, [{var_ref, "$pipe"} | Args], PipeEnv, Context));
expression_type({remote_call, _ModuleName, _FunctionName, _Args}, _Env, _Context) -> unknown;
expression_type({ffi_call, _ModuleName, _FunctionName, _Args, Returns}, _Env, _Context) ->
    single_return(Returns);
expression_type({call, Name, Args}, Env, Context) ->
    single_return(call_return_types(Name, Args, Env, Context));
expression_type({type_spec, Type}, _Env, _Context) -> Type;
expression_type(_Expression, _Env, _Context) -> unknown.

call_return_types("receive", [{type_spec, Type}], _Env, _Context) ->
    [Type];
call_return_types(Name, _Args, _Env, #{functions := Functions}) when is_list(Name) ->
    maps:get(Name, Functions, builtin_return_types(Name));
call_return_types(Name, Args, _Env, _Context) when is_atom(Name) ->
    constructor_return_types(Name, Args).

builtin_return_types("stdout") -> [atom];
builtin_return_types("print") -> [atom];
builtin_return_types("println") -> [atom];
builtin_return_types("eprint") -> [atom];
builtin_return_types("eprintln") -> [atom];
builtin_return_types("format") -> [string];
builtin_return_types("parse_int") -> [int];
builtin_return_types("parse_sint") -> [sint];
builtin_return_types("parse_float") -> [float];
builtin_return_types("parse_number") -> [number];
builtin_return_types("to_string") -> [string];
builtin_return_types("to_binary") -> [binary];
builtin_return_types("self") -> [pid];
builtin_return_types("spawn") -> [pid];
builtin_return_types("send") -> [atom];
builtin_return_types("receive") -> [unknown];
builtin_return_types(_Name) -> [unknown].

constructor_return_types(tuple, _Args) -> [tuple];
constructor_return_types(list, _Args) -> [list];
constructor_return_types(map, _Args) -> [map];
constructor_return_types(restricted_map, _Args) -> [restricted_map];
constructor_return_types(range, _Args) -> [list];
constructor_return_types(state, _Args) -> [state];
constructor_return_types(string, _Args) -> [string];
constructor_return_types(number, _Args) -> [number];
constructor_return_types(int, _Args) -> [int];
constructor_return_types(sint, _Args) -> [sint];
constructor_return_types(float, _Args) -> [float];
constructor_return_types(atom, _Args) -> [atom];
constructor_return_types(bool, _Args) -> [bool];
constructor_return_types(Name, _Args) -> [Name].

member_type(map, "count") -> int;
member_type(restricted_map, "count") -> int;
member_type(state, "count") -> int;
member_type(map, "members") -> list;
member_type(restricted_map, "members") -> list;
member_type(state, "members") -> list;
member_type(_Type, _Field) -> unknown.

binary_type(Op, _Left, _Right) when Op == eq_eq; Op == not_eq;
                                  Op == lt; Op == lt_eq;
                                  Op == gt; Op == gt_eq;
                                  Op == and_and; Op == or_or ->
    bool;
binary_type(div_op, _Left, _Right) ->
    float;
binary_type(_Op, float, _Right) -> float;
binary_type(_Op, _Left, float) -> float;
binary_type(_Op, number, _Right) -> number;
binary_type(_Op, _Left, number) -> number;
binary_type(_Op, sint, _Right) -> sint;
binary_type(_Op, _Left, sint) -> sint;
binary_type(_Op, _Left, _Right) -> int.

single_return([Type]) -> Type;
single_return([]) -> unknown;
single_return(_Types) -> tuple.

format_type_list(Types) ->
    lists:join(", ", [type_name(Type) || Type <- Types]).

expression_kind({try_call, Name, _Args}) -> ["try call to ", display_name(Name)];
expression_kind({pipe_call, _Left, _Name, _Args}) -> "pipeline";
expression_kind({remote_call, ModuleName, FunctionName, _Args}) ->
    ["imported call ", ModuleName, ".", FunctionName];
expression_kind({ffi_call, ModuleName, FunctionName, _Args, _Returns}) ->
    ["FFI call erlang.", ModuleName, ".", FunctionName];
expression_kind({call, Name, _Args}) -> ["call to ", display_name(Name)];
expression_kind({record, Name, _Fields}) -> [Name, " constructor"];
expression_kind({variant, EnumName, VariantName, _Fields}) -> [EnumName, ".", VariantName];
expression_kind({update, _Base, _Updates}) -> "immutable update";
expression_kind({pointer_new, _Value}) -> "pointer allocation";
expression_kind({pointer_read, _Value}) -> "pointer read";
expression_kind({member, _Value, Name}) -> ["member .", Name];
expression_kind({binary, Op, _Left, _Right}) -> ["binary ", atom_to_list(Op)];
expression_kind({unary, Op, _Value}) -> ["unary ", atom_to_list(Op)];
expression_kind({var_ref, Name}) -> ["binding ", Name];
expression_kind({list, _Values}) -> "list literal";
expression_kind({tuple, _Values}) -> "tuple literal";
expression_kind({map, _Pairs}) -> "map literal";
expression_kind(_Value) -> "literal".

else_text(none) -> " and no else branch";
else_text(_Else) -> " and an else branch".

invocation(once) -> "once";
invocation(repeated) -> "normally".

display_name(Name) when is_atom(Name) -> atom_to_list(Name);
display_name(Name) -> Name.

spaces(Indent) -> lists:duplicate(Indent * 2, $\s).

plural(1, Word) -> Word;
plural(_Count, Word) -> Word ++ "s".

pipe_stages({pipe_call, Left, _Name, _Args}) -> 1 + pipe_stages(Left);
pipe_stages(_Value) -> 0.

flatten_type(Type) ->
    lists:flatten(type_name(Type)).

type_name(number) -> "Number";
type_name(unknown) -> "unknown";
type_name(Type) when is_atom(Type); is_tuple(Type) -> datatypes:display_name(Type);
type_name(Type) -> io_lib:format("~p", [Type]).
