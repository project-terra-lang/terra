-module(program).
-export([parse/1, parse_file/1, entry_body/1]).

parse(Tokens) ->
    case parse_functions(Tokens, []) of
        {ok, Functions} -> validate_and_parse(Functions);
        Error -> Error
    end.

parse_file(Path) ->
    case tokenizer:tokenize_file(Path) of
        {ok, Tokens} -> parse(Tokens);
        Error -> Error
    end.

entry_body(#{entry := Entry, functions := Functions}) ->
    case [maps:get(body, F) || F <- Functions, maps:get(name, F) == Entry] of
        [Body] -> Body;
        _ -> []
    end.

parse_functions([], Acc) ->
    {ok, lists:reverse(Acc)};
parse_functions([{keyword, function} | Rest], Acc) ->
    case parse_return_types(Rest) of
        {ok, Types, [{id, Name}, {lparen, "("} | ParamTokens]} ->
            parse_function(Name, Types, ParamTokens, Acc);
        {ok, _Types, Other} -> {error, {expected_function_name, Other}};
        Error -> Error
    end;
parse_functions(Other, _Acc) ->
    {error, {expected_function_declaration, Other}}.

parse_function(Name, Types, Tokens, Acc) ->
    case parse_parameters(Tokens, []) of
        {ok, Params, [{lbrace, "{"} | BodyTokens]} ->
            case take_body(BodyTokens, 1, []) of
                {ok, Body, Rest} ->
                    Function = #{kind => function, name => Name, params => Params,
                                 return_type => return_type(Types),
                                 return_types => Types, body => Body},
                    parse_functions(Rest, [Function | Acc]);
                Error -> Error
            end;
        {ok, _Params, Other} -> {error, {expected_function_body, Other}};
        Error -> Error
    end.

parse_return_types([{keyword, Type} | Rest]) ->
    checked_type(Type, [Type], Rest, unknown_return_type);
parse_return_types([{lparen, "("} | Rest]) ->
    parse_type_list(Rest, []);
parse_return_types(Other) ->
    {error, {expected_return_type, Other}}.

parse_type_list([{keyword, Type}, {comma, ","} | Rest], Acc) ->
    case is_type(Type) of
        true -> parse_type_list(Rest, [Type | Acc]);
        false -> {error, {unknown_return_type, Type}}
    end;
parse_type_list([{keyword, Type}, {rparen, ")"} | Rest], Acc) ->
    checked_type(Type, lists:reverse([Type | Acc]), Rest, unknown_return_type);
parse_type_list(Other, _Acc) ->
    {error, {expected_return_type, Other}}.

checked_type(Type, Value, Rest, ErrorTag) ->
    case is_type(Type) of
        true -> {ok, Value, Rest};
        false -> {error, {ErrorTag, Type}}
    end.

return_type([Type]) -> Type;
return_type(Types) -> {multiple, Types}.

parse_parameters([{rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse(Acc), Rest};
parse_parameters([{keyword, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    case is_type(Type) of
        true -> parse_parameters(Rest, [#{type => Type, name => Name} | Acc]);
        false -> {error, {unknown_parameter_type, Type}}
    end;
parse_parameters([{keyword, Type}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    case is_type(Type) of
        true -> {ok, lists:reverse([#{type => Type, name => Name} | Acc]), Rest};
        false -> {error, {unknown_parameter_type, Type}}
    end;
parse_parameters(Other, _Acc) ->
    {error, {expected_parameter, Other}}.

take_body([], _Depth, _Acc) ->
    {error, unterminated_function_body};
take_body([T = {lbrace, "{"} | Rest], Depth, Acc) ->
    take_body(Rest, Depth + 1, [T | Acc]);
take_body([{rbrace, "}"} | Rest], 1, Acc) ->
    {ok, lists:reverse(Acc), Rest};
take_body([T = {rbrace, "}"} | Rest], Depth, Acc) ->
    take_body(Rest, Depth - 1, [T | Acc]);
take_body([T | Rest], Depth, Acc) ->
    take_body(Rest, Depth, [T | Acc]).

validate_and_parse(Functions) ->
    case duplicate_name(Functions, []) of
        none -> validate_main(Functions);
        "Main" -> {error, duplicate_entry_point};
        Name -> {error, {duplicate_function, Name}}
    end.

duplicate_name([], _Seen) -> none;
duplicate_name([F | Rest], Seen) ->
    Name = maps:get(name, F),
    case lists:member(Name, Seen) of
        true -> Name;
        false -> duplicate_name(Rest, [Name | Seen])
    end.

validate_main(Functions) ->
    case [F || F <- Functions, maps:get(name, F) == "Main"] of
        [] -> {error, missing_entry_point};
        [#{return_types := [number],
           params := [#{type := string, name := "Args"}]}] ->
            parse_bodies(Functions);
        [_] ->
            {error, {invalid_entry_point_signature,
                     "function Number Main(String Args) { ... }"}}
    end.

parse_bodies(Functions) ->
    Signatures = maps:from_list(
        [{maps:get(name, F), #{params => maps:get(params, F),
                              return_types => maps:get(return_types, F)}} || F <- Functions]),
    case parse_bodies(Functions, Signatures, []) of
        {ok, Parsed} ->
            {ok, #{kind => program, entry => "Main", functions => lists:reverse(Parsed)}};
        Error -> Error
    end.

parse_bodies([], _Signatures, Acc) -> {ok, Acc};
parse_bodies([F | Rest], Signatures, Acc) ->
    Env = maps:from_list([{maps:get(name, P), maps:get(type, P)}
                          || P <- maps:get(params, F)]),
    case parse_statements(maps:get(body, F), F, Signatures, Env, []) of
        {ok, Statements, _} ->
            case validate_legacy_variable_body(Statements, maps:get(body, F)) of
                ok ->
                    parse_bodies(Rest, Signatures,
                                 [F#{statements => Statements} | Acc]);
                Error -> Error
            end;
        {error, Reason} -> {error, {in_function, maps:get(name, F), Reason}}
    end.

validate_legacy_variable_body(Statements, Body) ->
    IsVariableStatement = fun(Statement) ->
        Kind = maps:get(kind, Statement),
        Kind == variable_declaration orelse Kind == unparsed_statement
    end,
    case lists:all(IsVariableStatement, Statements) of
        true ->
            case variables:parse(Body) of
                {ok, _Variables} -> ok;
                Error -> Error
            end;
        false -> ok
    end.

parse_statements([], _F, _Sigs, Env, Acc) ->
    {ok, lists:reverse(Acc), Env};
parse_statements([{keyword, for_each} | Rest], F, Sigs, Env, Acc) ->
    parse_for_each(Rest, F, Sigs, Env, Acc);
parse_statements([{keyword, 'for'} | Rest], F, Sigs, Env, Acc) ->
    parse_for_range(Rest, F, Sigs, Env, Acc);
parse_statements([{keyword, while} | Rest], F, Sigs, Env, Acc) ->
    parse_condition_loop(while, Rest, F, Sigs, Env, Acc);
parse_statements([{keyword, do_while} | Rest], F, Sigs, Env, Acc) ->
    parse_condition_loop(do_while, Rest, F, Sigs, Env, Acc);
parse_statements([{keyword, 'if'} | Rest], F, Sigs, Env, Acc) ->
    parse_if(Rest, F, Sigs, Env, Acc);
parse_statements([{keyword, unless} | Rest], F, Sigs, Env, Acc) ->
    parse_unless(Rest, F, Sigs, Env, Acc);
parse_statements([{keyword, return} | Rest], F, Sigs, Env, Acc) ->
    case parse_expr_list(Rest, endofline, Sigs, Env, []) of
        {ok, Values, Remaining} ->
            case expression_types(Values, Sigs, Env, []) of
                {ok, Actual} ->
                    Expected = maps:get(return_types, F),
                    case types_accept(Expected, Actual) of
                        true -> parse_statements(Remaining, F, Sigs, Env,
                                                 [#{kind => return, values => Values} | Acc]);
                        false -> {error, {return_type_mismatch, Expected, Actual}}
                    end;
                Error -> Error
            end;
        Error -> Error
    end;
parse_statements([{id, Name}, {lparen, "("} | Rest], F, Sigs, Env, Acc) ->
    parse_call_statement(Name, Rest, F, Sigs, Env, Acc);
parse_statements([{keyword, stdout}, {lparen, "("} | Rest], F, Sigs, Env, Acc) ->
    parse_call_statement(stdout, Rest, F, Sigs, Env, Acc);
parse_statements([{id, Name}, {endofline, ";"} | Rest], F, Sigs, Env, Acc) ->
    case validate_call(Name, [], Sigs, Env) of
        {ok, _} ->
            Stmt = #{kind => call, name => Name, args => [], invocation => once},
            parse_statements(Rest, F, Sigs, Env, [Stmt | Acc]);
        Error -> Error
    end;
parse_statements([{keyword, const}, {id, Name}, {equals, "="} | Rest],
                 F, Sigs, Env, Acc) ->
    case parse_expr(Rest, Sigs, Env) of
        {ok, Value, [{endofline, ";"} | Remaining]} ->
            case single_type(Value, Sigs, Env) of
                {ok, Type} ->
                    Stmt = #{kind => variable, scope => local, eval => const,
                             type => Type, name => Name, value => Value},
                    parse_statements(Remaining, F, Sigs, maps:put(Name, Type, Env),
                                     [Stmt | Acc]);
                Error -> Error
            end;
        {ok, _Value, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end;
parse_statements([{keyword, Scope}, {keyword, Type}, {id, Name}, {comma, ","} | Rest],
                 F, Sigs, Env, Acc)
  when Scope == global; Scope == local; Scope == temp ->
    case parse_bindings(Rest, [{Type, Name}]) of
        {ok, Bindings, [{equals, "="} | ValueTokens]} ->
            bind_multiple(Scope, Bindings, ValueTokens, F, Sigs, Env, Acc);
        {ok, _Bindings, Other} -> {error, {expected_equals, Other}};
        Error -> Error
    end;
parse_statements([{keyword, Scope} | _] = Tokens, F, Sigs, Env, Acc)
  when Scope == global; Scope == local; Scope == temp ->
    preserve_declaration(Tokens, F, Sigs, Env, Acc);
parse_statements(Tokens, F, Sigs, Env, Acc) ->
    preserve_statement(Tokens, F, Sigs, Env, Acc).

parse_call_statement(Name, Tokens, F, Sigs, Env, Acc) ->
    case parse_call(Name, Tokens, Sigs, Env) of
        {ok, {call, Name, Args}, [{endofline, ";"} | Remaining]} ->
            Stmt = #{kind => call, name => Name, args => Args, invocation => repeated},
            parse_statements(Remaining, F, Sigs, Env, [Stmt | Acc]);
        {ok, {call, Name, Args}, []} ->
            Stmt = #{kind => call, name => Name, args => Args, invocation => repeated},
            parse_statements([], F, Sigs, Env, [Stmt | Acc]);
        {ok, _Call, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end.

parse_for_each([{id, Binding}, {keyword, 'in'} | Rest], F, Sigs, Env, Acc) ->
    case parse_expr(Rest, Sigs, Env) of
        {ok, Iterable, [{lbrace, "{"} | BodyStart]} ->
            case single_type(Iterable, Sigs, Env) of
                {ok, IterableType} ->
                    case iterable_type(IterableType) of
                        true ->
                            LoopEnv = maps:put("it", var, maps:put(Binding, var, Env)),
                            parse_loop_body(for_each, BodyStart, Rest, F, Sigs, Env,
                                            LoopEnv, Acc,
                                            #{binding => Binding, iterable => Iterable});
                        false -> {error, {expected_iterable, IterableType}}
                    end;
                Error -> Error
            end;
        {ok, _Iterable, Other} -> {error, {expected_loop_body, Other}};
        Error -> Error
    end;
parse_for_each(Other, _F, _Sigs, _Env, _Acc) ->
    {error, {expected_for_each_binding, Other}}.

parse_for_range(Tokens, F, Sigs, Env, Acc) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, {call, range, Args} = Range, [{lbrace, "{"} | BodyStart]} ->
            LoopEnv = maps:put("it", int, Env),
            parse_loop_body('for', BodyStart, Tokens, F, Sigs, Env, LoopEnv, Acc,
                            #{iterator => Range, args => Args});
        {ok, OtherIterator, _Rest} -> {error, {expected_range_iterator, OtherIterator}};
        Error -> Error
    end.

parse_condition_loop(Kind, Tokens, F, Sigs, Env, Acc) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, Condition, [{lbrace, "{"} | BodyStart]} ->
            case require_bool(Condition, Sigs, Env) of
                ok ->
                    LoopEnv = maps:put("it", int, Env),
                    parse_loop_body(Kind, BodyStart, Tokens, F, Sigs, Env,
                                    LoopEnv, Acc, #{condition => Condition});
                Error -> Error
            end;
        {ok, _Condition, Other} -> {error, {expected_loop_body, Other}};
        Error -> Error
    end.

parse_loop_body(Kind, BodyStart, _Tokens, F, Sigs, Env, LoopEnv, Acc, Fields) ->
    case take_body(BodyStart, 1, []) of
        {ok, Body, Rest} ->
            case parse_statements(Body, F, Sigs, LoopEnv, []) of
                {ok, Statements, _} ->
                    Stmt = maps:merge(#{kind => Kind, statements => Statements}, Fields),
                    parse_statements(Rest, F, Sigs, Env, [Stmt | Acc]);
                Error -> Error
            end;
        Error -> Error
    end.

iterable_type(list) -> true;
iterable_type(tuple) -> true;
iterable_type(map) -> true;
iterable_type(string) -> true;
iterable_type(_) -> false.

parse_if(Tokens, F, Sigs, Env, Acc) ->
    case parse_add(Tokens, Sigs, Env) of
        {ok, Subject, [{eq_eq, "=="}, {lbrace, "{"} | BodyStart]} ->
            parse_switch(Subject, BodyStart, F, Sigs, Env, Acc);
        _ ->
            case parse_condition_branch(Tokens, F, Sigs, Env) of
                {ok, Branch, Remaining} ->
                    case parse_if_tail(Remaining, F, Sigs, Env, [Branch], none) of
                        {ok, Branches, ElseBranch, Rest} ->
                            Stmt = #{kind => 'if', branches => Branches,
                                     else_branch => ElseBranch},
                            parse_statements(Rest, F, Sigs, Env, [Stmt | Acc]);
                        Error -> Error
                    end;
                Error -> Error
            end
    end.

parse_condition_branch(Tokens, F, Sigs, Env) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, Condition, [{lbrace, "{"} | BodyStart]} ->
            case require_bool(Condition, Sigs, Env) of
                ok ->
                    case take_body(BodyStart, 1, []) of
                        {ok, Body, Rest} ->
                            case parse_statements(Body, F, Sigs, Env, []) of
                                {ok, Statements, _} ->
                                    {ok, #{condition => Condition,
                                           statements => Statements}, Rest};
                                Error -> Error
                            end;
                        Error -> Error
                    end;
                Error -> Error
            end;
        {ok, _Condition, Other} -> {error, {expected_condition_body, Other}};
        Error -> Error
    end.

parse_if_tail([{keyword, elseif} | Rest], F, Sigs, Env, Branches, none) ->
    case parse_condition_branch(Rest, F, Sigs, Env) of
        {ok, Branch, Remaining} ->
            parse_if_tail(Remaining, F, Sigs, Env, Branches ++ [Branch], none);
        Error -> Error
    end;
parse_if_tail([{keyword, 'else'}, {lbrace, "{"} | BodyStart], F, Sigs, Env,
              Branches, none) ->
    case take_body(BodyStart, 1, []) of
        {ok, Body, Rest} ->
            case parse_statements(Body, F, Sigs, Env, []) of
                {ok, Statements, _} -> {ok, Branches, Statements, Rest};
                Error -> Error
            end;
        Error -> Error
    end;
parse_if_tail(Rest, _F, _Sigs, _Env, Branches, ElseBranch) ->
    {ok, Branches, ElseBranch, Rest}.

parse_unless(Tokens, F, Sigs, Env, Acc) ->
    case parse_condition_branch(Tokens, F, Sigs, Env) of
        {ok, Branch, [{keyword, 'else'}, {lbrace, "{"} | BodyStart]} ->
            case take_body(BodyStart, 1, []) of
                {ok, ElseBody, Rest} ->
                    case parse_statements(ElseBody, F, Sigs, Env, []) of
                        {ok, ElseStatements, _} ->
                            Stmt = #{kind => unless,
                                     condition => maps:get(condition, Branch),
                                     statements => maps:get(statements, Branch),
                                     else_branch => ElseStatements},
                            parse_statements(Rest, F, Sigs, Env, [Stmt | Acc]);
                        Error -> Error
                    end;
                Error -> Error
            end;
        {ok, Branch, Rest} ->
            Stmt = #{kind => unless,
                     condition => maps:get(condition, Branch),
                     statements => maps:get(statements, Branch),
                     else_branch => none},
            parse_statements(Rest, F, Sigs, Env, [Stmt | Acc]);
        Error -> Error
    end.

parse_switch(Subject, BodyStart, F, Sigs, Env, Acc) ->
    case single_type(Subject, Sigs, Env) of
        {ok, SubjectType} ->
            case take_body(BodyStart, 1, []) of
                {ok, CaseTokens, Rest} ->
                    case parse_cases(CaseTokens, SubjectType, F, Sigs, Env, [], false) of
                        {ok, Cases, true} ->
                            Stmt = #{kind => switch, subject => Subject,
                                     cases => Cases, break => default,
                                     exhaustive => true},
                            parse_statements(Rest, F, Sigs, Env, [Stmt | Acc]);
                        {ok, _Cases, false} -> {error, non_exhaustive_switch};
                        Error -> Error
                    end;
                Error -> Error
            end;
        Error -> Error
    end.

parse_cases([], _SubjectType, _F, _Sigs, _Env, Acc, HasDefault) ->
    {ok, lists:reverse(Acc), HasDefault};
parse_cases([{keyword, 'case'}, {atomprefix, ":"} | Rest], SubjectType,
            F, Sigs, Env, Acc, false) ->
    parse_case_body(default, Rest, SubjectType, F, Sigs, Env, Acc, true);
parse_cases([{keyword, 'case'}, {atomprefix, ":"} | _Rest], _SubjectType,
            _F, _Sigs, _Env, _Acc, true) ->
    {error, duplicate_default_case};
parse_cases([{keyword, 'case'} | Rest], SubjectType, F, Sigs, Env, Acc, HasDefault) ->
    case parse_expr(Rest, Sigs, Env) of
        {ok, Pattern, [{atomprefix, ":"} | BodyTokens]} ->
            case single_type(Pattern, Sigs, Env) of
                {ok, PatternType} ->
                    case types_compatible(SubjectType, PatternType) of
                        true -> parse_case_body(Pattern, BodyTokens, SubjectType,
                                                F, Sigs, Env, Acc, HasDefault);
                        false ->
                            {error, {case_type_mismatch, SubjectType, PatternType}}
                    end;
                Error -> Error
            end;
        {ok, _Pattern, Other} -> {error, {expected_case_colon, Other}};
        Error -> Error
    end;
parse_cases(Other, _SubjectType, _F, _Sigs, _Env, _Acc, _HasDefault) ->
    {error, {expected_case, Other}}.

parse_case_body(Pattern, Tokens, SubjectType, F, Sigs, Env, Acc, HasDefault) ->
    {Body, Rest} = take_case_body(Tokens, 0, []),
    case Pattern == default andalso Rest =/= [] of
        true -> {error, default_case_must_be_last};
        false ->
            case parse_statements(Body, F, Sigs, Env, []) of
                {ok, Statements, _} ->
                    Case = #{pattern => Pattern, statements => Statements},
                    parse_cases(Rest, SubjectType, F, Sigs, Env,
                                [Case | Acc], HasDefault);
                Error -> Error
            end
    end.

take_case_body([], _Depth, Acc) -> {lists:reverse(Acc), []};
take_case_body([{keyword, 'case'} | _] = Rest, 0, Acc) ->
    {lists:reverse(Acc), Rest};
take_case_body([T = {lbrace, "{"} | Rest], Depth, Acc) ->
    take_case_body(Rest, Depth + 1, [T | Acc]);
take_case_body([T = {rbrace, "}"} | Rest], Depth, Acc) when Depth > 0 ->
    take_case_body(Rest, Depth - 1, [T | Acc]);
take_case_body([T | Rest], Depth, Acc) ->
    take_case_body(Rest, Depth, [T | Acc]).

require_bool(Condition, Sigs, Env) ->
    case single_type(Condition, Sigs, Env) of
        {ok, bool} -> ok;
        {ok, Type} -> {error, {expected_boolean_condition, Type}};
        Error -> Error
    end.

parse_bindings([{keyword, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_bindings(Rest, [{Type, Name} | Acc]);
parse_bindings([{keyword, Type}, {id, Name} | Rest], Acc) ->
    Bindings = lists:reverse([{Type, Name} | Acc]),
    case lists:all(fun({T, _}) -> is_type(T) end, Bindings) of
        true -> {ok, Bindings, Rest};
        false -> {error, unknown_variable_type}
    end;
parse_bindings(Other, _Acc) ->
    {error, {expected_multi_binding, Other}}.

bind_multiple(Scope, Bindings, Tokens, F, Sigs, Env, Acc) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, Value, [{endofline, ";"} | Remaining]} ->
            Expected = [Type || {Type, _} <- Bindings],
            case infer_types(Value, Sigs, Env) of
                {ok, Actual} ->
                    case types_accept(Expected, Actual) of
                        true ->
                            Items = [#{type => Type, name => Name} || {Type, Name} <- Bindings],
                            Stmt = #{kind => multi_binding, scope => Scope,
                                     bindings => Items, value => Value},
                            NewEnv = lists:foldl(fun({T, N}, E) -> maps:put(N, T, E) end,
                                                 Env, Bindings),
                            parse_statements(Remaining, F, Sigs, NewEnv, [Stmt | Acc]);
                        false -> {error, {return_type_mismatch, Expected, Actual}}
                    end;
                Error -> Error
            end;
        {ok, _Value, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end.

preserve_declaration(Tokens, F, Sigs, Env, Acc) ->
    case take_statement(Tokens, 0, []) of
        {ok, StatementTokens, Rest} ->
            Stmt = #{kind => variable_declaration, tokens => StatementTokens},
            NewEnv = track_declared_variable(StatementTokens, Env),
            parse_statements(Rest, F, Sigs, NewEnv, [Stmt | Acc]);
        Error -> Error
    end.

track_declared_variable([{keyword, Scope}, {keyword, Type}, {id, Name},
                         {equals, "="} | _], Env)
  when Scope == global; Scope == local; Scope == temp ->
    case is_type(Type) of
        true -> maps:put(Name, Type, Env);
        false -> Env
    end;
track_declared_variable([{keyword, Scope}, {keyword, Modifier}, {keyword, Type},
                         {id, Name}, {equals, "="} | _], Env)
  when (Scope == global orelse Scope == local orelse Scope == temp) andalso
       (Modifier == lazy orelse Modifier == const orelse Modifier == computed orelse
        Modifier == atomic orelse Modifier == thread_local) ->
    case is_type(Type) of
        true -> maps:put(Name, Type, Env);
        false -> Env
    end;
track_declared_variable(_Tokens, Env) ->
    Env.

preserve_statement(Tokens, F, Sigs, Env, Acc) ->
    case take_statement(Tokens, 0, []) of
        {ok, StatementTokens, Rest} ->
            Stmt = #{kind => unparsed_statement, tokens => StatementTokens},
            parse_statements(Rest, F, Sigs, Env, [Stmt | Acc]);
        Error -> Error
    end.

take_statement([], _Depth, _Acc) -> {error, unterminated_statement};
take_statement([T = {endofline, ";"} | Rest], 0, Acc) ->
    {ok, lists:reverse([T | Acc]), Rest};
take_statement([T = {lparen, "("} | Rest], Depth, Acc) ->
    take_statement(Rest, Depth + 1, [T | Acc]);
take_statement([T = {rparen, ")"} | Rest], Depth, Acc) when Depth > 0 ->
    take_statement(Rest, Depth - 1, [T | Acc]);
take_statement([T | Rest], Depth, Acc) ->
    take_statement(Rest, Depth, [T | Acc]).

parse_expr_list(Tokens, Close, Sigs, Env, Acc) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, Value, [{comma, ","} | Rest]} ->
            parse_expr_list(Rest, Close, Sigs, Env, [Value | Acc]);
        {ok, Value, [{Close, _} | Rest]} ->
            {ok, lists:reverse([Value | Acc]), Rest};
        {ok, _Value, Other} -> {error, {expected_separator_or_close, Other}};
        Error -> Error
    end.

parse_expr(Tokens, Sigs, Env) ->
    case parse_add(Tokens, Sigs, Env) of
        {ok, Left, [{Op, _} | Rest]}
          when Op == eq_eq; Op == not_eq; Op == lt; Op == lt_eq;
               Op == gt; Op == gt_eq ->
            case parse_add(Rest, Sigs, Env) of
                {ok, Right, Remaining} ->
                    {ok, {binary, Op, Left, Right}, Remaining};
                Error -> Error
            end;
        Result -> Result
    end.

parse_add(Tokens, Sigs, Env) ->
    case parse_mul(Tokens, Sigs, Env) of
        {ok, Left, Rest} -> parse_add_rest(Left, Rest, Sigs, Env);
        Error -> Error
    end.

parse_add_rest(Left, [{Op, _} | Rest], Sigs, Env) when Op == plus; Op == minus ->
    case parse_mul(Rest, Sigs, Env) of
        {ok, Right, Remaining} ->
            parse_add_rest({binary, Op, Left, Right}, Remaining, Sigs, Env);
        Error -> Error
    end;
parse_add_rest(Left, Rest, _Sigs, _Env) -> {ok, Left, Rest}.

parse_mul(Tokens, Sigs, Env) ->
    case parse_primary(Tokens, Sigs, Env) of
        {ok, Left, Rest} -> parse_mul_rest(Left, Rest, Sigs, Env);
        Error -> Error
    end.

parse_mul_rest(Left, [{Op, _} | Rest], Sigs, Env) when Op == times; Op == div_op ->
    case parse_primary(Rest, Sigs, Env) of
        {ok, Right, Remaining} ->
            parse_mul_rest({binary, Op, Left, Right}, Remaining, Sigs, Env);
        Error -> Error
    end;
parse_mul_rest(Left, Rest, _Sigs, _Env) -> {ok, Left, Rest}.

parse_primary([{int, V} | Rest], _Sigs, _Env) -> {ok, {int, V}, Rest};
parse_primary([{minus, "-"}, {int, V} | Rest], _Sigs, _Env) -> {ok, {sint, -V}, Rest};
parse_primary([{float, V} | Rest], _Sigs, _Env) -> {ok, {float, V}, Rest};
parse_primary([{minus, "-"}, {float, V} | Rest], _Sigs, _Env) -> {ok, {float, -V}, Rest};
parse_primary([{string, V} | Rest], _Sigs, _Env) -> {ok, {string, V}, Rest};
parse_primary([{char, V} | Rest], _Sigs, _Env) -> {ok, {char, V}, Rest};
parse_primary([{keyword, V} | Rest], _Sigs, _Env) when V == true; V == false ->
    {ok, {bool, V}, Rest};
parse_primary([{id, Name}, {lparen, "("} | Rest], Sigs, Env) ->
    parse_call(Name, Rest, Sigs, Env);
parse_primary([{keyword, Name}, {lparen, "("} | Rest], Sigs, Env) ->
    parse_call(Name, Rest, Sigs, Env);
parse_primary([{id, Name} | Rest], _Sigs, _Env) ->
    parse_members({var_ref, Name}, Rest);
parse_primary([{lparen, "("} | Rest], Sigs, Env) -> parse_group(Rest, Sigs, Env);
parse_primary(Other, _Sigs, _Env) -> {error, {expected_expression, Other}}.

parse_members(Value, [{dot, "."}, {id, Name} | Rest]) ->
    parse_members({member, Value, Name}, Rest);
parse_members(Value, Rest) ->
    {ok, Value, Rest}.

parse_group(Tokens, Sigs, Env) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, Value, [{comma, ","} | Rest]} ->
            parse_sequence(Rest, rparen, tuple, [Value], Sigs, Env);
        {ok, Value, [{rparen, ")"} | Rest]} -> {ok, Value, Rest};
        {ok, _Value, Other} -> {error, {expected_group_or_tuple_close, Other}};
        Error -> Error
    end.

parse_call(Name, [{rparen, ")"} | Rest], Sigs, Env) ->
    case validate_call(Name, [], Sigs, Env) of
        {ok, _} -> {ok, {call, Name, []}, Rest};
        Error -> Error
    end;
parse_call(Name, Tokens, Sigs, Env) ->
    case parse_sequence(Tokens, rparen, call_args, [], Sigs, Env) of
        {ok, {call_args, Args}, Rest} ->
            case validate_call(Name, Args, Sigs, Env) of
                {ok, _} -> {ok, {call, Name, Args}, Rest};
                Error -> Error
            end;
        Error -> Error
    end.

parse_sequence([{Close, _} | Rest], Close, Kind, Acc, _Sigs, _Env) ->
    {ok, {Kind, lists:reverse(Acc)}, Rest};
parse_sequence(Tokens, Close, Kind, Acc, Sigs, Env) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, Value, [{comma, ","} | Rest]} ->
            parse_sequence(Rest, Close, Kind, [Value | Acc], Sigs, Env);
        {ok, Value, [{Close, _} | Rest]} ->
            {ok, {Kind, lists:reverse([Value | Acc])}, Rest};
        {ok, _Value, Other} -> {error, {expected_separator_or_close, Other}};
        Error -> Error
    end.

validate_call(stdout, Args, Sigs, Env) ->
    case expression_types(Args, Sigs, Env, []) of
        {ok, _} -> {ok, []};
        Error -> Error
    end;
validate_call(range, Args, Sigs, Env) -> validate_range(Args, Sigs, Env);
validate_call(Name, Args, Sigs, Env) when is_list(Name) ->
    case maps:find(Name, Sigs) of
        {ok, #{params := Params, return_types := Returns}} ->
            Expected = [maps:get(type, P) || P <- Params],
            case expression_types(Args, Sigs, Env, []) of
                {ok, Actual} ->
                    case types_accept(Expected, Actual) of
                        true -> {ok, Returns};
                        false -> {error, {argument_type_mismatch, Name, Expected, Actual}}
                    end;
                Error -> Error
            end;
        error -> {error, {unknown_function, Name}}
    end;
validate_call(Name, Args, Sigs, Env) when is_atom(Name) ->
    case is_type(Name) of
        true ->
            case expression_types(Args, Sigs, Env, []) of
                {ok, _} -> {ok, [Name]};
                Error -> Error
            end;
        false -> {error, {unknown_function, Name}}
    end.

expression_types([], _Sigs, _Env, Acc) -> {ok, lists:reverse(Acc)};
expression_types([Expr | Rest], Sigs, Env, Acc) ->
    case infer_types(Expr, Sigs, Env) of
        {ok, Types} -> expression_types(Rest, Sigs, Env, lists:reverse(Types) ++ Acc);
        Error -> Error
    end.

single_type(Expr, Sigs, Env) ->
    case infer_types(Expr, Sigs, Env) of
        {ok, [Type]} -> {ok, Type};
        {ok, Types} -> {error, {expected_single_value, Types}};
        Error -> Error
    end.

infer_types({int, _}, _Sigs, _Env) -> {ok, [int]};
infer_types({sint, _}, _Sigs, _Env) -> {ok, [sint]};
infer_types({float, _}, _Sigs, _Env) -> {ok, [float]};
infer_types({string, _}, _Sigs, _Env) -> {ok, [string]};
infer_types({char, _}, _Sigs, _Env) -> {ok, [int]};
infer_types({bool, _}, _Sigs, _Env) -> {ok, [bool]};
infer_types({tuple, _}, _Sigs, _Env) -> {ok, [tuple]};
infer_types({member, Value, _Name}, Sigs, Env) ->
    case single_type(Value, Sigs, Env) of
        {ok, _Type} -> {ok, [var]};
        Error -> Error
    end;
infer_types({var_ref, Name}, _Sigs, Env) ->
    case maps:find(Name, Env) of
        {ok, Type} -> {ok, [Type]};
        error -> {error, {unknown_variable, Name}}
    end;
infer_types({call, Name, Args}, Sigs, Env) -> validate_call(Name, Args, Sigs, Env);
infer_types({binary, Op, Left, Right}, Sigs, Env) ->
    case {single_type(Left, Sigs, Env), single_type(Right, Sigs, Env)} of
        {{ok, LT}, {ok, RT}} -> binary_type(Op, LT, RT);
        {{error, Reason}, _} -> {error, Reason};
        {_, {error, Reason}} -> {error, Reason}
    end;
infer_types(_Expr, _Sigs, _Env) -> {error, unknown_type}.

binary_type(plus, string, string) -> {ok, [string]};
binary_type(Op, int, int) when Op == plus; Op == minus; Op == times -> {ok, [int]};
binary_type(div_op, int, int) -> {ok, [float]};
binary_type(Op, float, float) when Op == plus; Op == minus; Op == times; Op == div_op ->
    {ok, [float]};
binary_type(Op, Left, Right) when Op == eq_eq; Op == not_eq ->
    case types_compatible(Left, Right) of
        true -> {ok, [bool]};
        false -> {error, {type_mismatch, Left, Right}}
    end;
binary_type(Op, Left, Right) when Op == lt; Op == lt_eq; Op == gt; Op == gt_eq ->
    case orderable_types(Left, Right) of
        true -> {ok, [bool]};
        false -> {error, {type_mismatch, Left, Right}}
    end;
binary_type(_Op, Left, Right) -> {error, {type_mismatch, Left, Right}}.

types_compatible(Left, Right) ->
    type_accepts(Left, Right) orelse type_accepts(Right, Left).

orderable_types(Left, Right) ->
    (is_number_type(Left) andalso is_number_type(Right)) orelse
    (Left == string andalso Right == string).

is_number_type(number) -> true;
is_number_type(int) -> true;
is_number_type(sint) -> true;
is_number_type(float) -> true;
is_number_type(_) -> false.

validate_range([Limit], Sigs, Env) ->
    case single_type(Limit, Sigs, Env) of
        {ok, Type} ->
            case is_number_type(Type) of
                true -> {ok, [list]};
                false -> {error, {expected_range_number, Type}}
            end;
        Error -> Error
    end;
validate_range(Args, _Sigs, _Env) ->
    {error, {range_arity, 1, length(Args)}}.

types_accept(Expected, Actual) when length(Expected) == length(Actual) ->
    lists:all(fun({E, A}) -> type_accepts(E, A) end, lists:zip(Expected, Actual));
types_accept(_, _) -> false.

type_accepts(number, int) -> true;
type_accepts(number, sint) -> true;
type_accepts(number, float) -> true;
type_accepts(Type, Type) -> true;
type_accepts(_, _) -> false.

is_type(state) -> true;
is_type(var) -> true;
is_type(Type) -> datatypes:is_type(Type).
