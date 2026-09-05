#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Cases = [{"main ok", "tests/programs/main_ok.terra", fun expect_main_ok/1},
             {"functions", "tests/programs/functions.terra", fun expect_functions/1},
             {"control flow", "tests/programs/control_flow.terra", fun expect_control_flow/1},
             {"loops and recursion", "tests/programs/loops.terra", fun expect_loops/1},
             {"loop condition", "tests/programs/loops_bad_condition.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {expected_boolean_condition, int}}}
              end},
             {"loop iterable", "tests/programs/loops_bad_iterable.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main", {expected_iterable, int}}}
              end},
             {"non-boolean condition", "tests/programs/control_bad_condition.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {expected_boolean_condition, int}}}
              end},
             {"non-exhaustive switch", "tests/programs/control_non_exhaustive.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main", non_exhaustive_switch}}
              end},
             {"bad function return", "tests/programs/functions_bad_return.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "T",
                                      {return_type_mismatch,
                                       [string, number], [int, string]}}}
              end},
             {"bad multi binding", "tests/programs/functions_bad_binding.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {return_type_mismatch,
                                       [number, string], [string, number]}}}
              end},
             {"top level code", "tests/programs/top_level_code.terra",
              fun(Result) ->
                  case Result of
                      {error, {expected_function_declaration, _Tokens}} -> true;
                      _ -> false
                  end
              end},
             {"missing main", "tests/programs/missing_main.terra",
              fun(Result) -> Result =:= {error, missing_entry_point} end},
             {"bad signature", "tests/programs/main_bad_signature.terra",
              fun(Result) ->
                  Result =:= {error, {invalid_entry_point_signature,
                                      "function Number Main(String Args) { ... }"}}
              end}],
    Results = [run_case(Case) || Case <- Cases],
    case lists:member(fail, Results) of
        true ->
            io:format("program tests failed~n"),
            halt(1);
        false ->
            io:format("program tests passed~n"),
            ok
    end.

run_case({Name, Path, Expect}) ->
    Result = program:parse_file(Path),
    case Expect(Result) of
        true ->
            io:format("ok - ~s~n", [Name]),
            pass;
        false ->
            io:format("not ok - ~s~n  got: ~p~n", [Name, Result]),
            fail
    end.

expect_main_ok({ok, Program}) ->
    maps:get(kind, Program) == program andalso
    maps:get(entry, Program) == "Main" andalso
    length(maps:get(functions, Program)) == 1;
expect_main_ok(_) ->
    false.

expect_functions({ok, Program}) ->
    Functions = maps:get(functions, Program),
    T = find_function("T", Functions),
    Main = find_function("Main", Functions),
    MainStatements = maps:get(statements, Main),
    maps:get(return_types, T) == [string, number] andalso
    count_calls("FunctionA", repeated, MainStatements) == 2 andalso
    count_calls("FunctionA", once, MainStatements) == 1 andalso
    has_multi_binding(MainStatements);
expect_functions(_) ->
    false.

find_function(Name, Functions) ->
    hd([Function || Function <- Functions, maps:get(name, Function) == Name]).

count_calls(Name, Invocation, Statements) ->
    length([Statement || Statement <- Statements,
                         maps:get(kind, Statement) == call,
                         maps:get(name, Statement) == Name,
                         maps:get(invocation, Statement) == Invocation]).

has_multi_binding(Statements) ->
    lists:any(fun(Statement) ->
        maps:get(kind, Statement) == multi_binding andalso
        maps:get(bindings, Statement) ==
            [#{type => string, name => "x"}, #{type => number, name => "y"}] andalso
        maps:get(value, Statement) == {call, "T", []}
    end, Statements).

expect_control_flow({ok, Program}) ->
    Control = find_function("Control", maps:get(functions, Program)),
    Statements = maps:get(statements, Control),
    If = find_statement('if', Statements),
    Unless = find_statement(unless, Statements),
    Switch = find_statement(switch, Statements),
    length(maps:get(branches, If)) == 2 andalso
    length(maps:get(else_branch, If)) == 1 andalso
    maps:get(else_branch, Unless) =/= none andalso
    maps:get(exhaustive, Switch) == true andalso
    maps:get(break, Switch) == default andalso
    length(maps:get(cases, Switch)) == 2;
expect_control_flow(_) ->
    false.

find_statement(Kind, Statements) ->
    hd([Statement || Statement <- Statements, maps:get(kind, Statement) == Kind]).

expect_loops({ok, Program}) ->
    Functions = maps:get(functions, Program),
    LoopDemo = find_function("LoopDemo", Functions),
    Recur = find_function("Recur", Functions),
    LoopStatements = maps:get(statements, LoopDemo),
    RecurStatements = maps:get(statements, Recur),
    ForEach = find_statement(for_each, LoopStatements),
    ForRange = find_statement('for', LoopStatements),
    maps:get(binding, ForEach) == "x" andalso
    maps:get(iterable, ForEach) == {var_ref, "items"} andalso
    maps:get(iterator, ForRange) == {call, range, [{int, 10}]} andalso
    has_kind(while, LoopStatements) andalso
    has_kind(do_while, LoopStatements) andalso
    count_calls("Recur", repeated, RecurStatements) == 1;
expect_loops(_) ->
    false.

has_kind(Kind, Statements) ->
    lists:any(fun(Statement) -> maps:get(kind, Statement) == Kind end, Statements).
