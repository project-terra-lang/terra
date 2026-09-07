-module(warnings).
-export([analyze/1]).

analyze(#{functions := Functions}) ->
    lists:append([analyze_function(Function) || Function <- Functions]).

analyze_function(#{name := FunctionName, params := Params,
                   statements := Statements}) ->
    State0 = #{function => FunctionName, scopes => [#{}], bindings => #{},
               used => #{}, next_id => 1, warnings => []},
    State1 = lists:foldl(
        fun(Param, State) -> declare(maps:get(name, Param), parameter, true, State) end,
        State0, Params),
    maps:get(warnings, leave_scope(analyze_statements(Statements, State1))).

analyze_statements(Statements, State) ->
    lists:foldl(fun analyze_statement/2, State, Statements).

analyze_statement(#{kind := variable, name := Name, value := Value}, State) ->
    declare(Name, variable, true, analyze_expr(Value, State));
analyze_statement(#{kind := multi_binding, bindings := Bindings, value := Value}, State) ->
    lists:foldl(fun(Binding, Current) ->
        declare(maps:get(name, Binding), variable, true, Current)
    end, analyze_expr(Value, State), Bindings);
analyze_statement(#{kind := call, name := Name, args := Args}, State) ->
    State1 = analyze_exprs(Args, State),
    case is_list(Name) of
        true -> add_warning(ignored_return_value, #{callee => Name}, State1);
        false -> State1
    end;
analyze_statement(#{kind := pointer_write, pointer := Pointer, value := Value}, State) ->
    analyze_expr(Value, analyze_expr(Pointer, State));
analyze_statement(#{kind := return, values := Values}, State) ->
    analyze_exprs(Values, State);
analyze_statement(#{kind := 'if', branches := Branches, else_branch := Else}, State) ->
    State1 = lists:foldl(fun(Branch, Current) ->
        WithCondition = analyze_expr(maps:get(condition, Branch), Current),
        analyze_child(maps:get(statements, Branch), WithCondition)
    end, State, Branches),
    analyze_optional_child(Else, State1);
analyze_statement(#{kind := unless, condition := Condition,
                    statements := Statements, else_branch := Else}, State) ->
    State1 = analyze_child(Statements, analyze_expr(Condition, State)),
    analyze_optional_child(Else, State1);
analyze_statement(#{kind := switch, subject := Subject, cases := Cases}, State) ->
    lists:foldl(fun(Case, Current) ->
        analyze_case(Case, Current)
    end, analyze_expr(Subject, State), Cases);
analyze_statement(#{kind := for_each, binding := Binding, iterable := Iterable,
                    statements := Statements}, State) ->
    State1 = enter_scope(analyze_expr(Iterable, State)),
    State2 = declare(Binding, variable, true, State1),
    State3 = declare("it", implicit, false, State2),
    leave_scope(analyze_statements(Statements, State3));
analyze_statement(#{kind := 'for', iterator := Iterator, statements := Statements}, State) ->
    analyze_loop(Iterator, Statements, State);
analyze_statement(#{kind := Kind, condition := Condition, statements := Statements}, State)
  when Kind == while; Kind == do_while ->
    State1 = enter_scope(State),
    State2 = declare("it", implicit, false, State1),
    State3 = analyze_expr(Condition, State2),
    leave_scope(analyze_statements(Statements, State3));
analyze_statement(_Statement, State) -> State.

analyze_case(#{pattern := {variant_pattern, _Enum, _Variant, Bindings},
               statements := Statements}, State) ->
    Scoped = enter_scope(State),
    WithBindings = lists:foldl(fun
        (#{binding := ignore}, Current) -> Current;
        (#{binding := Name}, Current) -> declare(Name, variable, true, Current)
    end, Scoped, Bindings),
    leave_scope(analyze_statements(Statements, WithBindings));
analyze_case(#{pattern := default, statements := Statements}, State) ->
    analyze_child(Statements, State);
analyze_case(#{pattern := Pattern, statements := Statements}, State) ->
    analyze_child(Statements, analyze_expr(Pattern, State)).

analyze_loop(Iterator, Statements, State) ->
    State1 = enter_scope(analyze_expr(Iterator, State)),
    State2 = declare("it", implicit, false, State1),
    leave_scope(analyze_statements(Statements, State2)).

analyze_optional_child(none, State) -> State;
analyze_optional_child(Statements, State) -> analyze_child(Statements, State).

analyze_child(Statements, State) ->
    leave_scope(analyze_statements(Statements, enter_scope(State))).

analyze_expr({var_ref, Name}, State) -> mark_used(Name, State);
analyze_expr(Value, State) when is_tuple(Value) ->
    analyze_exprs(tuple_to_list(Value), State);
analyze_expr(Value, State) when is_list(Value) -> analyze_exprs(Value, State);
analyze_expr(_Value, State) -> State.

analyze_exprs(Values, State) -> lists:foldl(fun analyze_expr/2, State, Values).

enter_scope(State) -> State#{scopes := [#{} | maps:get(scopes, State)]}.

leave_scope(#{scopes := [Scope | Rest]} = State) ->
    %% Binding ids follow declaration order; never inherit map iteration order.
    BindingIds = lists:sort(maps:values(Scope)),
    State1 = lists:foldl(fun finalize_binding/2, State, BindingIds),
    State1#{scopes := Rest}.

declare(Name, Kind, WarnShadow, State) ->
    State1 = finalize_replaced_binding(Name, State),
    State2 = case WarnShadow andalso visible_binding(Name, State1) =/= none of
                 true -> add_warning(shadowed_variable, #{name => Name}, State1);
                 false -> State1
             end,
    Id = maps:get(next_id, State2),
    [Scope | Rest] = maps:get(scopes, State2),
    Binding = #{id => Id, name => Name, kind => Kind},
    Bindings = maps:put(Id, Binding, maps:get(bindings, State2)),
    State2#{scopes := [maps:put(Name, Id, Scope) | Rest],
            bindings := Bindings, next_id := Id + 1}.

finalize_replaced_binding(Name, #{scopes := [Scope | _]} = State) ->
    case maps:find(Name, Scope) of
        {ok, Id} -> finalize_binding(Id, State);
        error -> State
    end.

finalize_binding(Id, State) ->
    Binding = maps:get(Id, maps:get(bindings, State)),
    case maps:get(kind, Binding) == implicit orelse maps:is_key(Id, maps:get(used, State)) of
        true -> State;
        false ->
            Code = case maps:get(kind, Binding) of
                       parameter -> unused_parameter;
                       variable -> unused_variable
                   end,
            add_warning(Code, #{name => maps:get(name, Binding)}, State)
    end.

mark_used(Name, State) ->
    case visible_binding(Name, State) of
        none -> State;
        Id -> State#{used := maps:put(Id, true, maps:get(used, State))}
    end.

visible_binding(_Name, #{scopes := []}) -> none;
visible_binding(Name, #{scopes := [Scope | Rest]} = State) ->
    case maps:find(Name, Scope) of
        {ok, Id} -> Id;
        error -> visible_binding(Name, State#{scopes := Rest})
    end.

add_warning(Code, Fields, State) ->
    Warning = maps:merge(#{severity => warning, code => Code,
                           function => maps:get(function, State)}, Fields),
    State#{warnings := maps:get(warnings, State) ++ [Warning]}.
