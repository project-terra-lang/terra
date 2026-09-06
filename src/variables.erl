-module(variables).
-export([parse/1, parse_file/1, print_file/1]).

%% Parse variable declarations into a small structure the next compiler stages can use.
%% Variables are immutable, so reassignment is rejected while declarations may shadow.
%% Lazy variables keep their initializer deferred for later compiler stages.

parse(Tokens) ->
    SourceSpan = spans:tokens_span(Tokens),
    case parse_declarations(spans:strip_tokens(Tokens), [], []) of
        {ok, Variables} -> {ok, add_spans(Variables, SourceSpan)};
        Error -> Error
    end.

parse_file(Path) ->
    case tokenizer:tokenize_file(Path) of
        {error, Reason} ->
            {error, Reason};
        {ok, Tokens} ->
            parse(Tokens)
    end.

print_file(Path) ->
    case parse_file(Path) of
        {error, Reason} ->
            io:format("%% ERROR ~p~n", [Reason]),
            {error, Reason};
        {ok, Variables} ->
            io:format("[~p,~n", [filename:basename(Path)]),
            print_variables(Variables),
            io:format("]~n"),
            ok
    end.

parse_declarations([], _Env, Acc) ->
    {ok, lists:reverse(Acc)};
parse_declarations(Tokens, Env, Acc) ->
    case parse_statement(Tokens, Env) of
        {ok, Variable, NewEnv, Rest} ->
            parse_declarations(Rest, NewEnv, [Variable | Acc]);
        {ok, Variable, Rest} ->
            Name = maps:get(name, Variable),
            Entry = make_env_entry(Variable),
            Shadowed = env_has_name(Name, Env),
            parse_declarations(Rest, [Entry | Env], [Variable#{shadowed => Shadowed} | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

parse_statement([{id, Name}, {equals, "="} | _Rest], Env) ->
    case env_has_name(Name, Env) of
        true -> {error, {immutable_variable, Name}};
        false -> {error, {unknown_variable, Name}}
    end;
parse_statement([{keyword, Scope}, {lparen, "("} | Rest], Env)
  when Scope == global; Scope == local; Scope == temp ->
    parse_destructure(Scope, Rest, Env);
parse_statement(Tokens, Env) ->
    parse_declaration(Tokens, Env).

parse_declaration([{keyword, Scope}, {keyword, lazy}, {keyword, Type},
                   {id, Name}, {equals, "="} | Rest], Env)
  when Scope == global; Scope == local; Scope == temp ->
    parse_variable_declaration(Scope, Type, Name, Rest, Env, true, runtime, shared);
parse_declaration([{keyword, Scope}, {keyword, const}, {keyword, Type},
                   {id, Name}, {equals, "="} | Rest], Env)
  when Scope == global; Scope == local; Scope == temp ->
    parse_variable_declaration(Scope, Type, Name, Rest, Env, false, const, shared);
parse_declaration([{keyword, Scope}, {keyword, computed}, {keyword, Type},
                   {id, Name}, {equals, "="} | Rest], Env)
  when Scope == global; Scope == local; Scope == temp ->
    parse_variable_declaration(Scope, Type, Name, Rest, Env, false, computed, shared);
parse_declaration([{keyword, Scope}, {keyword, atomic}, {keyword, Type},
                   {id, Name}, {equals, "="} | Rest], Env)
  when Scope == global; Scope == local; Scope == temp ->
    parse_variable_declaration(Scope, Type, Name, Rest, Env, false, runtime, atomic);
parse_declaration([{keyword, Scope}, {keyword, thread_local}, {keyword, Type},
                   {id, Name}, {equals, "="} | Rest], Env)
  when Scope == global; Scope == local; Scope == temp ->
    parse_variable_declaration(Scope, Type, Name, Rest, Env, false, runtime, thread_local);
parse_declaration([{keyword, Scope}, {keyword, Type}, {id, Name}, {equals, "="} | Rest], Env)
  when Scope == global; Scope == local; Scope == temp ->
    parse_variable_declaration(Scope, Type, Name, Rest, Env, false, runtime, shared);
parse_declaration(Other, _Names) ->
    {error, {expected_variable_declaration, Other}}.

parse_variable_declaration(Scope, Type, Name, Rest, Env, Lazy, EvalMode, Concurrency) ->
    case is_type(Type) of
        false ->
            {error, {unknown_variable_type, Type}};
        true ->
            case parse_expr(Rest) of
                {ok, Value, [{endofline, ";"} | Remaining]} ->
                    Evaluated = maybe_eval_const(Value, Env, EvalMode),
                    case validate_value(Type, Evaluated, Env) of
                        {ok, InferredType} ->
                            case validate_storage(Scope, Lazy, EvalMode, Concurrency,
                                                  InferredType, Name, Evaluated) of
                                ok ->
                                    TypeInfo = describe_type(InferredType, wrap_lazy(Evaluated, Lazy), Env),
                                    {ok, #{scope => Scope, type => InferredType, name => Name,
                                           value => wrap_lazy(Evaluated, Lazy), lazy => Lazy,
                                           eval => EvalMode, accessor => accessor(EvalMode),
                                           concurrency => Concurrency, type_info => TypeInfo}, Remaining};
                                {error, Reason} ->
                                    {error, Reason}
                            end;
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {ok, _Value, Other} ->
                    {error, {expected_endofline, Other}};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

is_type(state) -> true;
is_type(var)   -> true;
is_type(Type)  -> datatypes:is_type(Type).

parse_expr(Tokens) ->
    parse_or(Tokens).

parse_or(Tokens) ->
    case parse_and(Tokens) of
        {ok, Left, Rest} -> parse_or_rest(Left, Rest);
        {error, Reason} -> {error, Reason}
    end.

parse_or_rest(Left, [{or_or, _Text} | Rest]) ->
    case parse_and(Rest) of
        {ok, Right, Remaining} ->
            parse_or_rest({binary, or_or, Left, Right}, Remaining);
        {error, Reason} ->
            {error, Reason}
    end;
parse_or_rest(Left, Rest) ->
    {ok, Left, Rest}.

parse_and(Tokens) ->
    case parse_compare(Tokens) of
        {ok, Left, Rest} -> parse_and_rest(Left, Rest);
        {error, Reason} -> {error, Reason}
    end.

parse_and_rest(Left, [{and_and, _Text} | Rest]) ->
    case parse_compare(Rest) of
        {ok, Right, Remaining} ->
            parse_and_rest({binary, and_and, Left, Right}, Remaining);
        {error, Reason} ->
            {error, Reason}
    end;
parse_and_rest(Left, Rest) ->
    {ok, Left, Rest}.

parse_compare(Tokens) ->
    case parse_add(Tokens) of
        {ok, Left, [{Op, _Text} | Rest]}
          when Op == eq_eq; Op == not_eq; Op == lt; Op == lt_eq;
               Op == gt; Op == gt_eq ->
            case parse_add(Rest) of
                {ok, Right, Remaining} ->
                    {ok, {binary, Op, Left, Right}, Remaining};
                {error, Reason} ->
                    {error, Reason}
            end;
        Result -> Result
    end.

parse_add(Tokens) ->
    case parse_mul(Tokens) of
        {ok, Left, Rest} -> parse_add_rest(Left, Rest);
        {error, Reason} -> {error, Reason}
    end.

parse_add_rest(Left, [{Op, _Text} | Rest]) when Op == plus; Op == minus ->
    case parse_mul(Rest) of
        {ok, Right, Remaining} ->
            parse_add_rest({binary, Op, Left, Right}, Remaining);
        {error, Reason} ->
            {error, Reason}
    end;
parse_add_rest(Left, Rest) ->
    {ok, Left, Rest}.

parse_mul(Tokens) ->
    case parse_unary(Tokens) of
        {ok, Left, Rest} -> parse_mul_rest(Left, Rest);
        {error, Reason} -> {error, Reason}
    end.

parse_mul_rest(Left, [{Op, _Text} | Rest]) when Op == times; Op == div_op ->
    case parse_primary(Rest) of
        {ok, Right, Remaining} ->
            parse_mul_rest({binary, Op, Left, Right}, Remaining);
        {error, Reason} ->
            {error, Reason}
    end;
parse_mul_rest(Left, Rest) ->
    {ok, Left, Rest}.

parse_unary([{minus, "-"}, {int, Value} | Rest]) ->
    {ok, {sint, -Value}, Rest};
parse_unary([{minus, "-"}, {float, Value} | Rest]) ->
    {ok, {float, -Value}, Rest};
parse_unary([{minus, "-"} | Rest]) ->
    case parse_unary(Rest) of
        {ok, Value, Remaining} -> {ok, {unary, minus, Value}, Remaining};
        {error, Reason} -> {error, Reason}
    end;
parse_unary([{bang, "!"} | Rest]) ->
    case parse_unary(Rest) of
        {ok, Value, Remaining} -> {ok, {unary, bang, Value}, Remaining};
        {error, Reason} -> {error, Reason}
    end;
parse_unary(Tokens) ->
    parse_primary(Tokens).

parse_primary([{int, Value} | Rest]) ->
    {ok, {int, Value}, Rest};
parse_primary([{float, Value} | Rest]) ->
    {ok, {float, Value}, Rest};
parse_primary([{string, Value} | Rest]) ->
    {ok, {string, Value}, Rest};
parse_primary([{keyword, true} | Rest]) ->
    {ok, {bool, true}, Rest};
parse_primary([{keyword, false} | Rest]) ->
    {ok, {bool, false}, Rest};
parse_primary([{keyword, null} | Rest]) ->
    {ok, null, Rest};
parse_primary([{keyword, nil} | Rest]) ->
    {ok, null, Rest};
parse_primary([{atomprefix, ":"}, {id, Name} | Rest]) ->
    {ok, {atom, list_to_atom(Name)}, Rest};
parse_primary([{id, Name}, {lparen, "("} | Rest]) ->
    parse_call(Name, Rest);
parse_primary([{keyword, Name}, {lparen, "("} | Rest]) ->
    parse_call(Name, Rest);
parse_primary([{id, Name} | Rest]) ->
    {ok, {var_ref, Name}, Rest};
parse_primary([{lbracket, "["} | Rest]) ->
    parse_sequence(Rest, rbracket, list, []);
parse_primary([{lparen, "("} | Rest]) ->
    parse_group_or_tuple(Rest);
parse_primary([{hash, "#"}, {lparen, "("} | Rest]) ->
    parse_map(Rest, []);
parse_primary(Other) ->
    {error, {expected_expression, Other}}.

parse_group_or_tuple(Tokens) ->
    case parse_expr(Tokens) of
        {ok, Value, [{comma, ","} | Rest]} ->
            parse_sequence(Rest, rparen, tuple, [Value]);
        {ok, Value, [{rparen, ")"} | Rest]} ->
            {ok, Value, Rest};
        {ok, _Value, Other} ->
            {error, {expected_group_or_tuple_close, Other}};
        {error, Reason} ->
            {error, Reason}
    end.

parse_call(Name, [{rparen, ")"} | Rest]) ->
    {ok, {call, Name, []}, Rest};
parse_call(Name, Rest) ->
    case parse_sequence(Rest, rparen, call_args, []) of
        {ok, {call_args, Args}, Remaining} ->
            {ok, {call, Name, Args}, Remaining};
        {error, Reason} ->
            {error, Reason}
    end.

parse_sequence([{Close, _} | Rest], Close, Kind, Acc) ->
    {ok, {Kind, lists:reverse(Acc)}, Rest};
parse_sequence(Tokens, Close, Kind, Acc) ->
    case parse_expr(Tokens) of
        {ok, Value, [{comma, ","} | Rest]} ->
            parse_sequence(Rest, Close, Kind, [Value | Acc]);
        {ok, Value, [{Close, _} | Rest]} ->
            {ok, {Kind, lists:reverse([Value | Acc])}, Rest};
        {ok, _Value, Other} ->
            {error, {expected_separator_or_close, Other}};
        {error, Reason} ->
            {error, Reason}
    end.

parse_map([{rparen, ")"} | Rest], Acc) ->
    {ok, {map, lists:reverse(Acc)}, Rest};
parse_map(Tokens, Acc) ->
    case parse_expr(Tokens) of
        {ok, Key, [{fat_arrow, "=>"} | Rest]} ->
            case parse_expr(Rest) of
                {ok, Value, [{comma, ","} | Next]} ->
                    parse_map(Next, [{Key, Value} | Acc]);
                {ok, Value, [{rparen, ")"} | Next]} ->
                    {ok, {map, lists:reverse([{Key, Value} | Acc])}, Next};
                {ok, _Value, Other} ->
                    {error, {expected_map_separator_or_close, Other}};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, _Key, Other} ->
            {error, {expected_fat_arrow, Other}};
        {error, Reason} ->
            {error, Reason}
    end.

print_variables([]) ->
    ok;
print_variables([Variable | Rest]) ->
    io:format("  ~p~n", [Variable]),
    print_variables(Rest).

validate_value(var, Value, Env) ->
    case infer_type(Value, Env) of
        {ok, Type} -> {ok, Type};
        {error, Reason} -> {error, Reason}
    end;
validate_value(Type, Value, Env) ->
    case infer_type(Value, Env) of
        {ok, ValueType} ->
            case type_accepts(Type, ValueType) of
                true -> {ok, Type};
                false -> {error, {type_mismatch, Type, Value}}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

maybe_eval_const(Value, Env, const) ->
    case eval_const(Value, Env) of
        {ok, Evaluated} -> Evaluated;
        {error, Reason} -> {const_error, Reason}
    end;
maybe_eval_const(Value, _Env, _EvalMode) ->
    Value.

eval_const({int, _} = Value, _Env) ->
    {ok, Value};
eval_const({sint, _} = Value, _Env) ->
    {ok, Value};
eval_const({float, _} = Value, _Env) ->
    {ok, Value};
eval_const({string, _} = Value, _Env) ->
    {ok, Value};
eval_const({bool, _} = Value, _Env) ->
    {ok, Value};
eval_const({atom, _} = Value, _Env) ->
    {ok, Value};
eval_const({var_ref, Name}, Env) ->
    case env_find(Name, Env) of
        {ok, #{eval := const, value := Value}} -> eval_const(Value, Env);
        {ok, _Entry} -> {error, {not_compile_time_constant, Name}};
        {error, Reason} -> {error, Reason}
    end;
eval_const({binary, Op, Left, Right}, Env) ->
    eval_binary_const(Op, Left, Right, Env);
eval_const({unary, Op, Value}, Env) ->
    case eval_const(Value, Env) of
        {ok, Evaluated} -> eval_unary(Op, Evaluated);
        {error, Reason} -> {error, Reason}
    end;
eval_const({call, Name, [Arg]}, Env)
  when Name == number; Name == int; Name == sint; Name == float ->
    case eval_const(Arg, Env) of
        {ok, Value} -> eval_numeric_conversion(Name, Value);
        {error, Reason} -> {error, Reason}
    end;
eval_const(_Value, _Env) ->
    {error, not_compile_time_constant}.

eval_binary_const(and_and, Left, Right, Env) ->
    case eval_const(Left, Env) of
        {ok, {bool, false}} -> {ok, {bool, false}};
        {ok, {bool, true}} -> eval_const(Right, Env);
        {ok, Other} -> {error, {invalid_const_expression, Other, and_and}};
        {error, Reason} -> {error, Reason}
    end;
eval_binary_const(or_or, Left, Right, Env) ->
    case eval_const(Left, Env) of
        {ok, {bool, true}} -> {ok, {bool, true}};
        {ok, {bool, false}} -> eval_const(Right, Env);
        {ok, Other} -> {error, {invalid_const_expression, Other, or_or}};
        {error, Reason} -> {error, Reason}
    end;
eval_binary_const(Op, Left, Right, Env) ->
    case {eval_const(Left, Env), eval_const(Right, Env)} of
        {{ok, LeftValue}, {ok, RightValue}} -> eval_binary(Op, LeftValue, RightValue);
        {{error, Reason}, _} -> {error, Reason};
        {_, {error, Reason}} -> {error, Reason}
    end.

eval_unary(bang, {bool, Value}) ->
    {ok, {bool, not Value}};
eval_unary(minus, {int, Value}) ->
    {ok, {sint, -Value}};
eval_unary(minus, {sint, Value}) ->
    {ok, {sint, -Value}};
eval_unary(minus, {float, Value}) ->
    {ok, {float, -Value}};
eval_unary(Op, Value) ->
    {error, {invalid_const_expression, Op, Value}}.

eval_binary(plus, {string, A}, {string, B}) ->
    {ok, {string, <<A/binary, B/binary>>}};
eval_binary(eq_eq, {bool, A}, {bool, B}) ->
    {ok, {bool, A == B}};
eval_binary(not_eq, {bool, A}, {bool, B}) ->
    {ok, {bool, A =/= B}};
eval_binary(and_and, {bool, A}, {bool, B}) ->
    {ok, {bool, A andalso B}};
eval_binary(or_or, {bool, A}, {bool, B}) ->
    {ok, {bool, A orelse B}};
eval_binary(Op, {LeftType, A}, {RightType, B})
  when (LeftType == int orelse LeftType == sint orelse LeftType == float),
       (RightType == int orelse RightType == sint orelse RightType == float),
       (Op == plus orelse Op == minus orelse Op == times orelse Op == div_op orelse
        Op == eq_eq orelse Op == not_eq orelse Op == lt orelse Op == lt_eq orelse
        Op == gt orelse Op == gt_eq) ->
    eval_numeric_binary(Op, LeftType, A, RightType, B);
eval_binary(_Op, Left, Right) ->
    {error, {invalid_const_expression, Left, Right}}.

eval_numeric_binary(div_op, _LeftType, _A, _RightType, B) when B == 0 ->
    {error, divide_by_zero};
eval_numeric_binary(div_op, _LeftType, A, _RightType, B) ->
    {ok, {float, A / B}};
eval_numeric_binary(eq_eq, _LeftType, A, _RightType, B) -> {ok, {bool, A == B}};
eval_numeric_binary(not_eq, _LeftType, A, _RightType, B) -> {ok, {bool, A /= B}};
eval_numeric_binary(lt, _LeftType, A, _RightType, B) -> {ok, {bool, A < B}};
eval_numeric_binary(lt_eq, _LeftType, A, _RightType, B) -> {ok, {bool, A =< B}};
eval_numeric_binary(gt, _LeftType, A, _RightType, B) -> {ok, {bool, A > B}};
eval_numeric_binary(gt_eq, _LeftType, A, _RightType, B) -> {ok, {bool, A >= B}};
eval_numeric_binary(Op, LeftType, A, RightType, B) ->
    Value = case Op of plus -> A + B; minus -> A - B; times -> A * B end,
    {ok, {numeric_result_type(Op, LeftType, RightType), Value}}.

eval_numeric_conversion(number, Value) -> {ok, Value};
eval_numeric_conversion(float, {_Type, Value}) when is_number(Value) ->
    {ok, {float, Value * 1.0}};
eval_numeric_conversion(sint, {_Type, Value}) when is_number(Value) ->
    {ok, {sint, trunc(Value)}};
eval_numeric_conversion(int, {_Type, Value}) when is_number(Value) ->
    {ok, {int, trunc(Value)}}.

parse_destructure(Scope, Tokens, Env) ->
    case parse_bindings(Tokens, []) of
        {ok, Bindings, [{equals, "="} | Rest]} ->
            case parse_expr(Rest) of
                {ok, Value, [{endofline, ";"} | Remaining]} ->
                    bind_destructure(Scope, Bindings, Value, Env, Remaining);
                {ok, _Value, Other} ->
                    {error, {expected_endofline, Other}};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, _Bindings, Other} ->
            {error, {expected_equals, Other}};
        {error, Reason} ->
            {error, Reason}
    end.

parse_bindings([{rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse(Acc), Rest};
parse_bindings([{keyword, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_binding(Type, Name, Rest, Acc);
parse_bindings([{keyword, Type}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    Bindings = lists:reverse([{Type, Name} | Acc]),
    case validate_binding_names(Bindings) of
        ok ->
            case is_type(Type) of
                true -> {ok, Bindings, Rest};
                false -> {error, {unknown_variable_type, Type}}
            end;
        Error -> Error
    end;
parse_bindings(Other, _Acc) ->
    {error, {expected_destructure_binding, Other}}.

parse_binding(Type, Name, Rest, Acc) ->
    case is_type(Type) of
        true -> parse_bindings(Rest, [{Type, Name} | Acc]);
        false -> {error, {unknown_variable_type, Type}}
    end.

validate_binding_names(Bindings) ->
    validate_binding_names(Bindings, []).

validate_binding_names([], _Seen) ->
    ok;
validate_binding_names([{_Type, Name} | Rest], Seen) ->
    case lists:member(Name, Seen) of
        true -> {error, {duplicate_variable, Name}};
        false -> validate_binding_names(Rest, [Name | Seen])
    end.

bind_destructure(Scope, Bindings, Value, Env, Remaining) ->
    case validate_destructure_source(Value, Env) of
        {ok, Values, SourceName} ->
            case bind_values(Scope, Bindings, Values, Env, []) of
                {ok, Variables, BoundEnv} ->
                    NewEnv = move_source(SourceName, BoundEnv),
                    {ok, #{scope => Scope, type => destructure, bindings => Variables, value => Value},
                     NewEnv, Remaining};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

validate_destructure_source({tuple, Values}, Env) ->
    case infer_type_list(Values, Env) of
        ok -> {ok, Values, none};
        {error, Reason} -> {error, Reason}
    end;
validate_destructure_source({var_ref, Name}, Env) ->
    case env_find(Name, Env) of
        {ok, #{state := moved}} ->
            {error, {use_after_move, Name}};
        {ok, #{type := tuple, value := {tuple, Values}}} ->
            {ok, Values, Name};
        {ok, #{type := Type}} ->
            {error, {cannot_destructure, Type}};
        {error, Reason} ->
            {error, Reason}
    end;
validate_destructure_source(Value, _Env) ->
    {error, {cannot_destructure, Value}}.

bind_values(_Scope, [], [], Env, Acc) ->
    {ok, lists:reverse(Acc), Env};
bind_values(_Scope, [], _Values, _Env, _Acc) ->
    {error, destructure_arity_mismatch};
bind_values(_Scope, _Bindings, [], _Env, _Acc) ->
    {error, destructure_arity_mismatch};
bind_values(Scope, [{Type, Name} | Bindings], [Value | Values], Env, Acc) ->
    case validate_value(Type, Value, Env) of
        {ok, InferredType} ->
            Shadowed = env_has_name(Name, Env),
            TypeInfo = describe_type(InferredType, Value, Env),
            Variable = #{scope => Scope, type => InferredType, name => Name,
                         value => Value, shadowed => Shadowed, lazy => false,
                         eval => runtime, accessor => direct, concurrency => shared,
                         type_info => TypeInfo},
            Entry = make_env_entry(Variable),
            bind_values(Scope, Bindings, Values, [Entry | Env], [Variable | Acc]);
        {error, Reason} ->
            {error, Reason}
    end.

infer_type(null, _Env) ->
    {error, null_not_allowed};
infer_type({const_error, Reason}, _Env) ->
    {error, Reason};
infer_type({lazy, Value}, Env) ->
    infer_type(Value, Env);
infer_type({int, _}, _Env) ->
    {ok, int};
infer_type({sint, _}, _Env) ->
    {ok, sint};
infer_type({float, _}, _Env) ->
    {ok, float};
infer_type({string, _}, _Env) ->
    {ok, string};
infer_type({bool, _}, _Env) ->
    {ok, bool};
infer_type({atom, _}, _Env) ->
    {ok, atom};
infer_type({list, Items}, Env) ->
    case infer_type_list(Items, Env) of
        ok -> {ok, list};
        {error, Reason} -> {error, Reason}
    end;
infer_type({tuple, Items}, Env) ->
    case infer_type_list(Items, Env) of
        ok -> {ok, tuple};
        {error, Reason} -> {error, Reason}
    end;
infer_type({map, Pairs}, Env) ->
    case infer_type_pairs(Pairs, Env) of
        ok -> {ok, map};
        {error, Reason} -> {error, Reason}
    end;
infer_type({binary, Op, Left, Right}, Env) ->
    case {infer_type(Left, Env), infer_type(Right, Env)} of
        {{ok, LeftType}, {ok, RightType}} -> infer_binary_type(Op, LeftType, RightType);
        {{error, Reason}, _} -> {error, Reason};
        {_, {error, Reason}} -> {error, Reason}
    end;
infer_type({unary, Op, Value}, Env) ->
    case infer_type(Value, Env) of
        {ok, Type} -> infer_unary_type(Op, Type);
        {error, Reason} -> {error, Reason}
    end;
infer_type({call, state, Args}, Env) ->
    case infer_type_list(Args, Env) of
        ok -> {ok, state};
        {error, Reason} -> {error, Reason}
    end;
infer_type({call, Name, Args}, Env)
  when Name == number; Name == int; Name == sint; Name == float ->
    infer_numeric_conversion(Name, Args, Env);
infer_type({call, Name, Args}, Env) ->
    case infer_type_list(Args, Env) of
        ok -> {ok, {call, Name}};
        {error, Reason} -> {error, Reason}
    end;
infer_type({var_ref, Name}, Env) ->
    case env_find(Name, Env) of
        {ok, #{state := moved}} -> {error, {use_after_move, Name}};
        {ok, #{type := Type}} -> {ok, Type};
        {error, Reason} -> {error, Reason}
    end;
infer_type(_Value, _Env) ->
    {error, unknown_type}.

infer_type_list([], _Env) ->
    ok;
infer_type_list([Value | Rest], Env) ->
    case infer_type(Value, Env) of
        {ok, _Type} -> infer_type_list(Rest, Env);
        {error, Reason} -> {error, Reason}
    end.

infer_type_pairs([], _Env) ->
    ok;
infer_type_pairs([{Key, Value} | Rest], Env) ->
    case infer_type(Key, Env) of
        {ok, _KeyType} ->
            case infer_type(Value, Env) of
                {ok, _ValueType} -> infer_type_pairs(Rest, Env);
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

type_accepts(number, int)   -> true;
type_accepts(number, sint)  -> true;
type_accepts(number, float) -> true;
type_accepts(Type, Type)    -> true;
type_accepts(_Type, _ValueType) -> false.

infer_binary_type(plus, string, string) ->
    {ok, string};
infer_binary_type(div_op, Left, Right) ->
    infer_numeric_binary_type(div_op, Left, Right);
infer_binary_type(Op, Left, Right) when Op == plus; Op == minus; Op == times ->
    infer_numeric_binary_type(Op, Left, Right);
infer_binary_type(Op, bool, bool)
  when Op == eq_eq; Op == not_eq; Op == and_and; Op == or_or ->
    {ok, bool};
infer_binary_type(Op, Left, Right)
  when Op == eq_eq; Op == not_eq ->
    case (is_number_type(Left) andalso is_number_type(Right)) orelse
         type_accepts(Left, Right) orelse type_accepts(Right, Left) of
        true -> {ok, bool};
        false -> {error, {type_mismatch, Left, Right}}
    end;
infer_binary_type(Op, Left, Right)
  when Op == lt; Op == lt_eq; Op == gt; Op == gt_eq ->
    case orderable_types(Left, Right) of
        true -> {ok, bool};
        false -> {error, {type_mismatch, Left, Right}}
    end;
infer_binary_type(_Op, LeftType, RightType) ->
    {error, {type_mismatch, LeftType, RightType}}.

infer_unary_type(bang, bool) ->
    {ok, bool};
infer_unary_type(minus, int) -> {ok, sint};
infer_unary_type(minus, Type) when Type == sint; Type == float; Type == number ->
    {ok, Type};
infer_unary_type(minus, Type) -> {error, {type_mismatch, number, Type}};
infer_unary_type(_Op, Type) ->
    {error, {type_mismatch, unknown, Type}}.

infer_numeric_conversion(Target, [Arg], Env) ->
    case infer_type(Arg, Env) of
        {ok, Source} ->
            case is_number_type(Source) of
                true -> {ok, Target};
                false -> {error, {invalid_numeric_conversion, Source, Target}}
            end;
        Error -> Error
    end;
infer_numeric_conversion(Target, Args, _Env) ->
    {error, {numeric_conversion_arity, Target, 1, length(Args)}}.

infer_numeric_binary_type(Op, Left, Right) ->
    case is_number_type(Left) andalso is_number_type(Right) of
        true -> {ok, numeric_result_type(Op, Left, Right)};
        false -> {error, {type_mismatch, Left, Right}}
    end.

numeric_result_type(div_op, _Left, _Right) -> float;
numeric_result_type(_Op, number, _Right) -> number;
numeric_result_type(_Op, _Left, number) -> number;
numeric_result_type(_Op, float, _Right) -> float;
numeric_result_type(_Op, _Left, float) -> float;
numeric_result_type(_Op, sint, _Right) -> sint;
numeric_result_type(_Op, _Left, sint) -> sint;
numeric_result_type(_Op, int, int) -> int.

orderable_types(Left, Right) ->
    (is_number_type(Left) andalso is_number_type(Right)) orelse
    (Left == string andalso Right == string).

is_number_type(number) -> true;
is_number_type(int) -> true;
is_number_type(sint) -> true;
is_number_type(float) -> true;
is_number_type(_) -> false.

accessor(computed) ->
    computed;
accessor(_EvalMode) ->
    direct.

validate_concurrency(shared, _Type) ->
    ok;
validate_concurrency(thread_local, _Type) ->
    ok;
validate_concurrency(atomic, int) ->
    ok;
validate_concurrency(atomic, sint) ->
    ok;
validate_concurrency(atomic, Type) ->
    {error, {invalid_atomic_type, Type}}.

validate_storage(global, _Lazy, _EvalMode, thread_local, _Type, _Name, _Value) ->
    {error, {invalid_storage_combination, global, thread_local}};
validate_storage(global, _Lazy, computed, _Concurrency, _Type, _Name, _Value) ->
    {error, {invalid_storage_combination, global, computed}};
validate_storage(global, true, _EvalMode, _Concurrency, _Type, _Name, _Value) ->
    {error, {invalid_storage_combination, global, lazy}};
validate_storage(global, _Lazy, _EvalMode, Concurrency, Type, Name, Value) ->
    case validate_concurrency(Concurrency, Type) of
        ok ->
            case expression_has_variable_reference(Value) of
                true -> {error, {global_initializer_not_closed, Name}};
                false -> ok
            end;
        Error -> Error
    end;
validate_storage(_Scope, _Lazy, _EvalMode, Concurrency, Type, _Name, _Value) ->
    validate_concurrency(Concurrency, Type).

expression_has_variable_reference({var_ref, _Name}) -> true;
expression_has_variable_reference(Value) when is_tuple(Value) ->
    lists:any(fun expression_has_variable_reference/1, tuple_to_list(Value));
expression_has_variable_reference(Value) when is_list(Value) ->
    lists:any(fun expression_has_variable_reference/1, Value);
expression_has_variable_reference(Value) when is_map(Value) ->
    lists:any(fun expression_has_variable_reference/1, maps:values(Value));
expression_has_variable_reference(_Value) -> false.

describe_type(number, {int, _Value}, _Env) ->
    #{kind => number, subtype => int};
describe_type(number, {sint, _Value}, _Env) ->
    #{kind => number, subtype => sint};
describe_type(number, {float, _Value}, _Env) ->
    #{kind => number, subtype => float};
describe_type(Type, {lazy, Value}, Env) ->
    (describe_type(Type, Value, Env))#{deferred => true};
describe_type(list, {list, Items}, Env) ->
    #{kind => list, element_types => unique_types(Items, Env)};
describe_type(tuple, {tuple, Items}, Env) ->
    #{kind => tuple, item_types => value_types(Items, Env), size => length(Items)};
describe_type(map, {map, Pairs}, Env) ->
    Keys = [Key || {Key, _Value} <- Pairs],
    Values = [Value || {_Key, Value} <- Pairs],
    #{kind => map, key_types => unique_types(Keys, Env), value_types => unique_types(Values, Env)};
describe_type(Type, _Value, _Env) ->
    datatypes:type_info(Type).

value_types(Values, Env) ->
    [value_type(Value, Env) || Value <- Values].

unique_types(Values, Env) ->
    lists:usort(value_types(Values, Env)).

value_type(Value, Env) ->
    case infer_type(Value, Env) of
        {ok, Type} -> Type;
        {error, Reason} -> {error, Reason}
    end.

wrap_lazy(Value, true) ->
    {lazy, Value};
wrap_lazy(Value, false) ->
    Value.

make_env_entry(Variable) ->
    State = case maps:get(lazy, Variable, false) of
        true -> deferred;
        false -> live
    end,
    #{name => maps:get(name, Variable),
      type => maps:get(type, Variable),
      value => maps:get(value, Variable),
      state => State,
      eval => maps:get(eval, Variable, runtime),
      accessor => maps:get(accessor, Variable, direct),
      concurrency => maps:get(concurrency, Variable, shared),
      type_info => maps:get(type_info, Variable, #{kind => maps:get(type, Variable)})}.

env_has_name(Name, Env) ->
    lists:any(fun(Entry) -> maps:get(name, Entry) == Name end, Env).

env_find(Name, Env) ->
    case [Entry || Entry <- Env, maps:get(name, Entry) == Name] of
        [Entry | _] -> {ok, Entry};
        [] -> {error, {unknown_variable, Name}}
    end.

move_source(none, Env) ->
    Env;
move_source(Name, Env) ->
    [mark_moved(Name, Entry) || Entry <- Env].

mark_moved(Name, Entry) ->
    case maps:get(name, Entry) == Name of
        true -> Entry#{state => moved};
        false -> Entry
    end.

add_spans(Value, Span) when is_list(Value) ->
    [add_spans(Item, Span) || Item <- Value];
add_spans(Value, Span) when is_map(Value) ->
    WithChildren = case maps:find(bindings, Value) of
                       {ok, Bindings} -> Value#{bindings => add_spans(Bindings, Span)};
                       error -> Value
                   end,
    case is_variable_node(WithChildren) andalso not maps:is_key(span, WithChildren) of
        true -> WithChildren#{span => Span};
        false -> WithChildren
    end;
add_spans(Value, _Span) ->
    Value.

is_variable_node(#{scope := _Scope, type := _Type}) ->
    true;
is_variable_node(_Value) ->
    false.
