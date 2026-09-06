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
                                      {expected_boolean_condition, int, {int, 10}}}}
              end},
             {"loop iterable", "tests/programs/loops_bad_iterable.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {expected_iterable, int, {int, 10}}}}
              end},
             {"non-boolean condition", "tests/programs/control_bad_condition.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {expected_boolean_condition, int, {int, 1}}}}
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
                      {error, {with_span, {expected_function_declaration, _Tokens}, Span}} ->
                          maps:get(start, Span) == #{line => 1, column => 1, offset => 0};
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
              end},
             {"void return type", "tests/programs/void_return_type.terra",
              fun(Result) -> Result =:= {error, void_return_type} end},
             {"missing return type", "tests/programs/missing_return_type.terra",
              fun expect_missing_return_type/1},
             {"empty return", "tests/programs/empty_return.terra",
              fun expect_empty_return/1},
             {"missing return", "tests/programs/missing_return.terra",
              fun expect_missing_return/1},
             {"partial branch return", "tests/programs/partial_branch_return.terra",
              fun expect_partial_branch_return/1},
             {"unreachable after return", "tests/programs/unreachable_after_return.terra",
              fun expect_unreachable_after_return/1},
             {"duplicate parameter", "tests/programs/duplicate_param.terra",
              fun(Result) -> Result =:= {error, {duplicate_variable, "Args"}} end},
             {"duplicate multi binding", "tests/programs/duplicate_multi_binding.terra",
              fun expect_duplicate_binding/1},
             {"duplicate destructure binding", "tests/programs/duplicate_destructure_binding.terra",
              fun expect_duplicate_binding/1},
             {"duplicate case", "tests/programs/duplicate_case.terra",
              fun expect_duplicate_case/1},
             {"invalid loop shadowing", "tests/programs/invalid_loop_shadowing.terra",
              fun expect_invalid_loop_shadowing/1},
             {"branch binding does not leak", "tests/programs/branch_binding_leak.terra",
              fun expect_branch_binding_leak/1},
             {"switch binding does not leak", "tests/programs/switch_binding_leak.terra",
              fun expect_switch_binding_leak/1},
             {"loop binding does not leak", "tests/programs/loop_binding_leak.terra",
              fun expect_loop_binding_leak/1},
             {"explicit compiler passes", "tests/programs/main_ok.terra",
              fun expect_passes/1},
             {"complete ast has no raw-token fallbacks",
              "examples/feature_showcase.terra", fun expect_complete_ast/1}],
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

expect_branch_binding_leak({error, {in_function, "Main", {unknown_variable, "branch_value"}}}) ->
    true;
expect_branch_binding_leak(_) ->
    false.

expect_switch_binding_leak({error, {in_function, "Main", {unknown_variable, "case_value"}}}) ->
    true;
expect_switch_binding_leak(_) ->
    false.

expect_loop_binding_leak({error, {in_function, "Main", {unknown_variable, "it"}}}) ->
    true;
expect_loop_binding_leak(_) ->
    false.

expect_missing_return_type({error, {with_span, {expected_return_type, _Tokens}, _Span}}) ->
    true;
expect_missing_return_type({error, {expected_return_type, _Tokens}}) ->
    true;
expect_missing_return_type(_) ->
    false.

expect_empty_return({error, {in_function, "Main",
                             {with_span, {expected_expression, _Tokens}, _Span}}}) ->
    true;
expect_empty_return({error, {in_function, "Main", {expected_expression, _Tokens}}}) ->
    true;
expect_empty_return(_) ->
    false.

expect_passes({ok, Program}) ->
    Expected = [parsing, name_resolution, type_checking, unreachable_code,
                definite_return, lowering],
    program:passes() == Expected andalso maps:get(passes, Program) == Expected;
expect_passes(_) ->
    false.

expect_missing_return({error, {in_function, "Main", {missing_return, [number]}}}) ->
    true;
expect_missing_return(_) ->
    false.

expect_partial_branch_return({error, {in_function, "Main", {missing_return, [number]}}}) ->
    true;
expect_partial_branch_return(_) ->
    false.

expect_unreachable_after_return({error, {in_function, "Main",
                                         {unreachable_statement, call}}}) ->
    true;
expect_unreachable_after_return(_) ->
    false.

expect_duplicate_binding({error, {in_function, "Main",
                                  {duplicate_variable, "value"}}}) ->
    true;
expect_duplicate_binding(_) ->
    false.

expect_duplicate_case({error, {in_function, "Main", {duplicate_case, {int, 1}}}}) ->
    true;
expect_duplicate_case(_) ->
    false.

expect_invalid_loop_shadowing({error, {in_function, "Main",
                                       {invalid_shadowing, "it"}}}) ->
    true;
expect_invalid_loop_shadowing(_) ->
    false.

expect_complete_ast({ok, Program}) ->
    not has_raw_fallback(Program);
expect_complete_ast(_) ->
    false.

has_raw_fallback(Value) when is_map(Value) ->
    maps:is_key(tokens, Value) orelse
    maps:get(kind, Value, none) == unparsed_statement orelse
    maps:get(kind, Value, none) == variable_declaration orelse
    lists:any(fun has_raw_fallback/1, maps:values(Value));
has_raw_fallback(Value) when is_list(Value) ->
    lists:any(fun has_raw_fallback/1, Value);
has_raw_fallback(_Value) ->
    false.
