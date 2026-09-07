#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Results = [run_case(Case) || Case <- cases()],
    case lists:member(fail, Results) of
        true ->
            io:format("variable tests failed~n"),
            halt(1);
        false ->
            io:format("variable tests passed~n"),
            ok
    end.

cases() ->
    [{"basic variables", "tests/variables/basic_variables.terra", fun expect_basic/1},
     {"data type metadata", "tests/variables/data_types.terra", fun expect_data_types/1},
     {"restricted map metadata and properties", "tests/variables/restricted_map.terra",
      fun expect_restricted_map/1},
     {"signed integer", "tests/variables/sint.terra", fun expect_sint/1},
     {"immutable reassignment", "tests/variables/immutable_reassign.terra",
      fun(Result) ->
          Result =:= {error, {immutable_variable, "x"}} orelse
          Result =:= {error, {in_function, "Main", {immutable_variable, "x"}}}
      end},
     {"type inference", "tests/variables/inference.terra", fun expect_inference/1},
     {"null rejection", "tests/variables/null_rejected.terra",
      fun(Result) ->
          Result =:= {error, null_not_allowed} orelse
          Result =:= {error, {in_function, "Main", null_not_allowed}}
      end},
     {"destructuring", "tests/variables/destructure.terra", fun expect_destructure/1},
     {"use after move", "tests/variables/use_after_move.terra",
      fun(Result) -> Result =:= {error, {use_after_move, "pair"}} end},
     {"shadowing", "tests/variables/shadowing.terra", fun expect_shadowing/1},
     {"lazy variable", "tests/variables/lazy.terra", fun expect_lazy/1},
     {"const and computed", "tests/variables/const_computed.terra", fun expect_const_computed/1},
     {"operator precedence", "tests/variables/operator_precedence.terra", fun expect_operator_precedence/1},
     {"boolean operators", "tests/variables/boolean_operators.terra", fun expect_boolean_operators/1},
     {"numeric rules", "tests/variables/numeric_rules.terra", fun expect_numeric_rules/1},
     {"const division by zero", "tests/variables/divide_by_zero.terra",
      fun(Result) -> Result =:= {error, divide_by_zero} end},
     {"const runtime rejection", "tests/variables/const_runtime_rejected.terra",
      fun(Result) -> Result =:= {error, {not_compile_time_constant, "base"}} end},
     {"concurrency", "tests/variables/concurrency.terra", fun expect_concurrency/1},
     {"invalid atomic", "tests/variables/invalid_atomic.terra",
      fun(Result) ->
          Result =:= {error, {invalid_atomic_type, string}} orelse
          Result =:= {error, {in_function, "Main", {invalid_atomic_type, string}}}
      end}].

run_case({Name, Path, Expect}) ->
    Result = parse_main_variables(Path),
    case Expect(Result) of
        true ->
            io:format("ok - ~s~n", [Name]),
            pass;
        false ->
            io:format("not ok - ~s~n  got: ~p~n", [Name, Result]),
            fail
    end.

parse_main_variables(Path) ->
    case program:parse_file(Path) of
        {ok, Program} ->
            variables:parse(declaration_tokens(program:entry_body(Program)));
        {error, Reason} ->
            {error, Reason}
    end.

declaration_tokens([{keyword, return} | _Rest]) ->
    [];
declaration_tokens([Token | Rest]) ->
    [Token | declaration_tokens(Rest)];
declaration_tokens([]) ->
    [].

expect_basic({ok, Vars}) ->
    length(Vars) == 8 andalso
    has_var("x", number, {int, 10}, Vars) andalso
    has_var("tag", atom, {atom, ready}, Vars) andalso
    has_var("ok", bool, {bool, true}, Vars) andalso
    has_var("lookup", map, {map, [{{var_ref, "x"}, {atom, value}}]}, Vars) andalso
    has_var("nums", list, {list, [{int, 1}, {int, 2}, {int, 3}]}, Vars) andalso
    has_var("pair", tuple, {tuple, [{int, 1}, {string, <<"one">>}]}, Vars) andalso
    has_var("name", string, {string, <<"terra">>}, Vars) andalso
    has_var("ratio", float, {float, 10.5}, Vars);
expect_basic(_) ->
    false.

expect_data_types({ok, Vars}) ->
    has_type_info("count", #{kind => number, subtype => int}, Vars) andalso
    has_type_info("ratio", #{kind => number, subtype => float}, Vars) andalso
    has_type_info("nums", #{kind => list, element_types => [int]}, Vars) andalso
    has_type_info("pair", #{kind => tuple, item_types => [int, string], size => 2}, Vars) andalso
    has_type_info("lookup", #{kind => map, key_types => [atom], value_types => [number]}, Vars);
expect_data_types(_) ->
    false.

expect_restricted_map({ok, Vars}) ->
    has_type_info("limited",
                  #{kind => restricted_map, capacity => 3, count => 2,
                    key_types => [atom], value_types => [int]}, Vars) andalso
    has_var("limited_count", int, {member, {var_ref, "limited"}, "count"}, Vars) andalso
    has_var("limited_members", list, {member, {var_ref, "limited"}, "members"}, Vars) andalso
    has_var("normal_count", int, {member, {var_ref, "normal"}, "count"}, Vars) andalso
    has_var("normal_members", list, {member, {var_ref, "normal"}, "members"}, Vars);
expect_restricted_map(_) ->
    false.

expect_sint({ok, Vars}) ->
    has_var("debt", sint, {sint, -5}, Vars) andalso
    has_var("score", number, {var_ref, "debt"}, Vars);
expect_sint(_) ->
    false.

expect_inference({ok, Vars}) ->
    has_var("x", int, {int, 10}, Vars) andalso
    has_var("y", int, {var_ref, "x"}, Vars) andalso
    has_var("label", string, {string, <<"terra">>}, Vars);
expect_inference(_) ->
    false.

expect_destructure({ok, [Pair, Destructure]}) ->
    maps:get(name, Pair) == "pair" andalso
    maps:get(type, Pair) == tuple andalso
    maps:get(type, Destructure) == destructure andalso
    has_var("id", int, {int, 1}, maps:get(bindings, Destructure)) andalso
    has_var("label", string, {string, <<"one">>}, maps:get(bindings, Destructure));
expect_destructure(_) ->
    false.

expect_shadowing({ok, Vars}) ->
    has_shadowed("data", string, false, Vars) andalso
    has_shadowed("data", int, true, Vars) andalso
    has_var("copy", int, {var_ref, "data"}, Vars);
expect_shadowing(_) ->
    false.

expect_lazy({ok, Vars}) ->
    has_lazy("expensive", int, {lazy, {int, 10}}, true, Vars) andalso
    has_var("copy", int, {var_ref, "expensive"}, Vars);
expect_lazy(_) ->
    false.

expect_const_computed({ok, Vars}) ->
    has_eval("base", int, {int, 2}, const, direct, Vars) andalso
    has_eval("total", int, {int, 5}, const, direct, Vars) andalso
    has_eval("next", int, {binary, plus, {var_ref, "total"}, {int, 1}}, computed, computed, Vars);
expect_const_computed(_) ->
    false.

expect_operator_precedence({ok, Vars}) ->
    has_eval("precedence", int, {int, 7}, const, direct, Vars) andalso
    has_eval("grouped", int, {int, 9}, const, direct, Vars) andalso
    has_eval("ordered", int, {int, 5}, const, direct, Vars) andalso
    has_eval("runtime_order", int,
             {binary, plus, {var_ref, "precedence"},
              {binary, times, {var_ref, "grouped"}, {var_ref, "ordered"}}},
             computed, computed, Vars);
expect_operator_precedence(_) ->
    false.

expect_boolean_operators({ok, Vars}) ->
    has_eval("guarded", bool, {bool, false}, const, direct, Vars) andalso
    has_eval("choice", bool, {bool, true}, const, direct, Vars) andalso
    has_eval("runtime_choice", bool,
             {binary, or_or, {var_ref, "choice"}, {var_ref, "guarded"}},
             computed, computed, Vars);
expect_boolean_operators(_) ->
    false.

expect_numeric_rules({ok, Vars}) ->
    has_eval("difference", int, {int, -3}, const, direct, Vars) andalso
    has_eval("ratio", float, {float, 2.5}, const, direct, Vars) andalso
    has_eval("mixed", float, {float, 3.5}, const, direct, Vars) andalso
    has_eval("comparison", bool, {bool, true}, const, direct, Vars) andalso
    has_eval("narrowed", int, {int, 3}, const, direct, Vars) andalso
    has_eval("signed", sint, {sint, -3}, const, direct, Vars);
expect_numeric_rules(_) ->
    false.

expect_concurrency({ok, Vars}) ->
    has_concurrency("counter", int, atomic, Vars) andalso
    has_concurrency("session", string, thread_local, Vars) andalso
    has_concurrency("snapshot", int, shared, Vars);
expect_concurrency(_) ->
    false.

has_var(Name, Type, Value, Vars) ->
    lists:any(fun(Var) ->
        maps:get(name, Var, none) == Name andalso
        maps:get(type, Var, none) == Type andalso
        maps:get(value, Var, none) == Value
    end, Vars).

has_type_info(Name, TypeInfo, Vars) ->
    lists:any(fun(Var) ->
        maps:get(name, Var, none) == Name andalso
        maps:get(type_info, Var, none) == TypeInfo
    end, Vars).

has_shadowed(Name, Type, Shadowed, Vars) ->
    lists:any(fun(Var) ->
        maps:get(name, Var, none) == Name andalso
        maps:get(type, Var, none) == Type andalso
        maps:get(shadowed, Var, none) == Shadowed
    end, Vars).

has_lazy(Name, Type, Value, Lazy, Vars) ->
    lists:any(fun(Var) ->
        maps:get(name, Var, none) == Name andalso
        maps:get(type, Var, none) == Type andalso
        maps:get(value, Var, none) == Value andalso
        maps:get(lazy, Var, none) == Lazy
    end, Vars).

has_eval(Name, Type, Value, Eval, Accessor, Vars) ->
    lists:any(fun(Var) ->
        maps:get(name, Var, none) == Name andalso
        maps:get(type, Var, none) == Type andalso
        maps:get(value, Var, none) == Value andalso
        maps:get(eval, Var, none) == Eval andalso
        maps:get(accessor, Var, none) == Accessor
    end, Vars).

has_concurrency(Name, Type, Concurrency, Vars) ->
    lists:any(fun(Var) ->
        maps:get(name, Var, none) == Name andalso
        maps:get(type, Var, none) == Type andalso
        maps:get(concurrency, Var, none) == Concurrency
    end, Vars).
