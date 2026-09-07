-module(terra_module_declarations).
-export([main/1]).

-file("tests/programs/module_declarations.terra", 5).
main(Args) ->
    terra_fn_main(terra_args(Args)).

-file("tests/programs/module_declarations.terra", 5).
terra_fn_main(Terra_Args_1) ->
    try
        Terra_base_2 = 2,
        Terra_inferred_3 = (Terra_base_2 + 1),
        Terra_shared_4 = terra_global("shared", fun() -> (Terra_inferred_3 + 4) end),
        throw({terra_return, Terra_shared_4}),
        0
    catch
        throw:{terra_return, TerraReturnValue} -> TerraReturnValue
    end.

-file("terra_runtime", 1).
terra_args(Value) when is_binary(Value) -> Value;
terra_args(Value) -> unicode:characters_to_binary(Value).

terra_ffi_return(Expected, Module, Function, Value) ->
    case terra_ffi_valid(Expected, Value) of
        true -> Value;
        false -> erlang:error({invalid_erlang_return, Module, Function, Expected, Value})
    end.

terra_ffi_valid(number, Value) -> is_number(Value);
terra_ffi_valid(int, Value) -> is_integer(Value) andalso Value >= 0;
terra_ffi_valid(sint, Value) -> is_integer(Value);
terra_ffi_valid(float, Value) -> is_float(Value);
terra_ffi_valid(atom, Value) -> is_atom(Value);
terra_ffi_valid(bool, Value) -> Value =:= true orelse Value =:= false;
terra_ffi_valid(string, Value) -> is_binary(Value);
terra_ffi_valid(list, Value) -> is_list(Value);
terra_ffi_valid(tuple, Value) -> is_tuple(Value);
terra_ffi_valid(map, Value) -> is_map(Value);
terra_ffi_valid(restricted_map, {terra_restricted_map, Capacity, Value}) ->
    is_integer(Capacity) andalso Capacity >= 0 andalso is_map(Value)
        andalso map_size(Value) =< Capacity;
terra_ffi_valid({named, Name}, #{'$terra_struct' := Name}) -> true;
terra_ffi_valid({named, Name}, #{'$terra_enum' := Name}) -> true;
terra_ffi_valid({multiple, Types}, Value) when is_tuple(Value) ->
    Values = tuple_to_list(Value),
    length(Types) =:= length(Values) andalso
        lists:all(fun({Type, Item}) -> terra_ffi_valid(Type, Item) end,
                  lists:zip(Types, Values));
terra_ffi_valid(_Expected, _Value) -> false.

terra_export_argument(Expected, Function, Position, Value) ->
    case terra_ffi_valid(Expected, Value) of
        true -> Value;
        false -> erlang:error({invalid_erlang_argument, Function, Position, Expected, Value})
    end.

terra_export_return(Expected, Function, Value) ->
    case terra_ffi_valid(Expected, Value) of
        true -> Value;
        false -> erlang:error({invalid_terra_export_return, Function, Expected, Value})
    end.

terra_stdout([]) -> io:nl();
terra_stdout(Values) ->
    lists:foreach(fun terra_stdout_value/1, Values),
    ok.

terra_stdout_value(Value) when is_binary(Value) -> io:format("~ts~n", [Value]);
terra_stdout_value(Value) -> io:format("~tp~n", [Value]).

terra_to_int(Value) when is_integer(Value) -> Value;
terra_to_int(Value) when is_float(Value) -> trunc(Value).

terra_to_sint(Value) when is_integer(Value) -> Value;
terra_to_sint(Value) when is_float(Value) -> trunc(Value).

terra_to_float(Value) when is_float(Value) -> Value;
terra_to_float(Value) when is_integer(Value) -> float(Value).

terra_parse_int(Value) when is_binary(Value) ->
    try binary_to_integer(Value)
    catch _:_ -> erlang:error({invalid_conversion, string, int, Value}) end.

terra_parse_sint(Value) when is_binary(Value) ->
    try binary_to_integer(Value)
    catch _:_ -> erlang:error({invalid_conversion, string, sint, Value}) end.

terra_parse_float(Value) when is_binary(Value) ->
    try binary_to_float(Value)
    catch _:_ -> erlang:error({invalid_conversion, string, float, Value}) end.

terra_parse_number(Value) when is_binary(Value) ->
    try binary_to_integer(Value)
    catch _:_ ->
        try binary_to_float(Value)
        catch _:_ -> erlang:error({invalid_conversion, string, number, Value}) end
    end.

terra_to_string(Value) when is_binary(Value) -> Value;
terra_to_string(Value) when is_integer(Value) -> integer_to_binary(Value);
terra_to_string(Value) when is_float(Value) -> float_to_binary(Value, [short]);
terra_to_string(Value) when is_atom(Value) -> atom_to_binary(Value, utf8).

terra_to_binary(Value) -> terra_to_string(Value).

terra_global(Key, Fun) ->
    StoreKey = {?MODULE, terra_global, Key},
    case persistent_term:get(StoreKey, terra_missing) of
        {done, Value} -> Value;
        terra_missing -> terra_initialize_global(StoreKey, Fun)
    end.

terra_initialize_global(StoreKey, Fun) ->
    RunningKey = {?MODULE, terra_global_running, StoreKey},
    case erlang:get(RunningKey) of
        true -> erlang:error({terra_global_reentrant, StoreKey});
        undefined ->
            erlang:put(RunningKey, true),
            try
                global:trans({StoreKey, self()}, fun() ->
                    case persistent_term:get(StoreKey, terra_missing) of
                        {done, Existing} -> Existing;
                        terra_missing ->
                            Value = Fun(),
                            persistent_term:put(StoreKey, {done, Value}),
                            Value
                    end
                end)
            after erlang:erase(RunningKey) end
    end.

terra_thread_local(Key, Fun) ->
    StoreKey = {?MODULE, terra_thread_local, Key},
    case erlang:get(StoreKey) of
        undefined ->
            erlang:put(StoreKey, running),
            try
                Value = Fun(),
                erlang:put(StoreKey, {done, Value}),
                Value
            catch
                Class:Reason:Stacktrace ->
                    erlang:erase(StoreKey),
                    erlang:raise(Class, Reason, Stacktrace)
            end;
        running -> erlang:error({terra_thread_local_reentrant, Key});
        {done, Value} -> Value
    end.

terra_atomic(Value) when is_integer(Value) ->
    Ref = atomics:new(1, [{signed, true}]),
    ok = atomics:put(Ref, 1, Value),
    Ref.

terra_global_atomic(Key, Fun) ->
    terra_global({atomic, Key}, fun() -> terra_atomic(Fun()) end).

terra_once(Key, Fun) ->
    StoreKey = {?MODULE, terra_once, Key},
    case erlang:get(StoreKey) of
        undefined ->
            erlang:put(StoreKey, running),
            try
                Value = Fun(),
                erlang:put(StoreKey, {done, Value}),
                Value
            catch
                Class:Reason:Stacktrace ->
                    erlang:erase(StoreKey),
                    erlang:raise(Class, Reason, Stacktrace)
            end;
        running -> erlang:error({terra_once_reentrant, Key});
        {done, Value} -> Value
    end.

terra_try(Fun) ->
    try Fun()
    catch
        Class:Reason:Stacktrace -> erlang:raise(Class, Reason, Stacktrace)
    end.

terra_pipe(ValueFun, NextFun) ->
    terra_try(fun() -> NextFun(ValueFun()) end).

terra_range(Limit) when Limit =< 0 -> [];
terra_range(Limit) -> lists:seq(0, trunc(Limit) - 1).

terra_for_range(Limit, Fun) -> lists:foreach(Fun, terra_range(Limit)).

terra_for_each(Value, Fun) ->
    Items = terra_iterable(Value),
    Indexed = lists:zip(Items, lists:seq(0, length(Items) - 1)),
    lists:foreach(fun({Item, Index}) -> Fun(Item, Index) end, Indexed).

terra_iterable({terra_restricted_map, _Capacity, Value}) -> maps:to_list(Value);
terra_iterable(Value) when is_list(Value) -> Value;
terra_iterable(Value) when is_tuple(Value) -> tuple_to_list(Value);
terra_iterable(Value) when is_map(Value) -> maps:to_list(Value);
terra_iterable(Value) when is_binary(Value) -> binary_to_list(Value).

terra_while(Condition, Body) -> terra_while(Condition, Body, 0).
terra_while(Condition, Body, It) ->
    case Condition(It) of
        true -> Body(It), terra_while(Condition, Body, It + 1);
        false -> ok
    end.

terra_do_while(Condition, Body) -> terra_do_while(Condition, Body, 0).
terra_do_while(Condition, Body, It) ->
    Body(It),
    case Condition(It) of
        true -> terra_do_while(Condition, Body, It + 1);
        false -> ok
    end.

terra_restricted_map(Capacity, Value)
  when is_integer(Capacity), Capacity >= 0, is_map(Value), map_size(Value) =< Capacity ->
    {terra_restricted_map, Capacity, Value};
terra_restricted_map(Capacity, Value) ->
    erlang:error({invalid_restricted_map, Capacity, Value}).

terra_update({terra_restricted_map, Capacity, Value}, Updates) ->
    terra_restricted_map(Capacity, terra_apply_updates(Value, Updates));
terra_update(Value, Updates) when is_map(Value) ->
    terra_apply_updates(Value, Updates);
terra_update(Value, _Updates) -> erlang:error({cannot_update, Value}).

terra_apply_updates(Value, []) -> Value;
terra_apply_updates(Value, [{Key, Next} | Rest]) ->
    terra_apply_updates(maps:put(Key, Next, Value), Rest).

terra_member({terra_restricted_map, _Capacity, Value}, count) -> map_size(Value);
terra_member({terra_restricted_map, _Capacity, Value}, members) -> maps:to_list(Value);
terra_member({terra_restricted_map, _Capacity, Value}, Key) -> maps:get(Key, Value);
terra_member(Value, count) when is_map(Value) -> map_size(Value);
terra_member(Value, members) when is_map(Value) -> maps:to_list(Value);
terra_member(Value, Key) when is_map(Value) -> maps:get(Key, Value);
terra_member(Value, Key) -> erlang:error({cannot_access_member, Key, Value}).
