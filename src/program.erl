-module(program).
-export([parse/1, parse_file/1, entry_body/1, passes/0]).

parse(Tokens) ->
    Context = #{tokens => Tokens,
                legacy_tokens => spans:strip_tokens(Tokens),
                source_span => spans:tokens_span(Tokens),
                completed_passes => []},
    case run_passes(pass_pipeline(), Context) of
        {ok, #{program := Program}} -> {ok, Program};
        Error -> annotate_error(Error, Tokens)
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

passes() ->
    [Name || {Name, _Pass} <- pass_pipeline()].

pass_pipeline() ->
    [{parsing, fun parsing_pass/1},
     {name_resolution, fun name_resolution_pass/1},
     {type_checking, fun type_checking_pass/1},
     {definite_return, fun definite_return_pass/1},
     {lowering, fun lowering_pass/1}].

run_passes([], Context) ->
    {ok, Context};
run_passes([{Name, Pass} | Rest], Context) ->
    case Pass(Context) of
        {ok, NextContext} ->
            Completed = maps:get(completed_passes, NextContext, []),
            run_passes(Rest, NextContext#{completed_passes => [Name | Completed]});
        Error -> Error
    end.

parsing_pass(#{legacy_tokens := Tokens} = Context) ->
    case parse_functions(Tokens, []) of
        {ok, Functions} -> {ok, Context#{functions => Functions}};
        Error -> Error
    end.

name_resolution_pass(#{functions := Functions} = Context) ->
    case duplicate_name(Functions, []) of
        none ->
            case validate_main_function(Functions) of
                ok ->
                    {ok, Context#{entry => "Main", signatures => signatures(Functions)}};
                Error -> Error
            end;
        "Main" -> {error, duplicate_entry_point};
        Name -> {error, {duplicate_function, Name}}
    end.

type_checking_pass(#{functions := Functions, signatures := Signatures,
                     entry := Entry} = Context) ->
    case parse_bodies(Functions, Signatures, []) of
        {ok, Parsed} ->
            Program = #{kind => program, entry => Entry,
                        functions => lists:reverse(Parsed)},
            {ok, Context#{program => Program}};
        Error -> Error
    end.

definite_return_pass(#{program := #{functions := Functions}} = Context) ->
    case first_missing_return(Functions) of
        none -> {ok, Context};
        #{name := Name, return_types := ReturnTypes} ->
            {error, {in_function, Name, {missing_return, ReturnTypes}}}
    end.

lowering_pass(#{program := Program, source_span := SourceSpan,
                completed_passes := Completed} = Context) ->
    Passes = lists:reverse([lowering | Completed]),
    Lowered = (add_ast_spans(Program, SourceSpan))#{passes => Passes},
    {ok, Context#{program => Lowered}}.

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
    case Type of
        void -> {error, void_return_type};
        _ ->
            case is_type(Type) of
                true -> {ok, Value, Rest};
                false -> {error, {ErrorTag, Type}}
            end
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

duplicate_name([], _Seen) -> none;
duplicate_name([F | Rest], Seen) ->
    Name = maps:get(name, F),
    case lists:member(Name, Seen) of
        true -> Name;
        false -> duplicate_name(Rest, [Name | Seen])
    end.

validate_main_function(Functions) ->
    case [F || F <- Functions, maps:get(name, F) == "Main"] of
        [] -> {error, missing_entry_point};
        [#{return_types := [number],
           params := [#{type := string, name := "Args"}]}] ->
            ok;
        [_] ->
            {error, {invalid_entry_point_signature,
                     "function Number Main(String Args) { ... }"}}
    end.

signatures(Functions) ->
    maps:from_list(
        [{maps:get(name, F), #{params => maps:get(params, F),
                              return_types => maps:get(return_types, F)}} || F <- Functions]).

env_from_bindings(Bindings) ->
    [maps:from_list(Bindings)].

env_child(Env) ->
    [#{} | Env].

env_put(Name, Type, [Scope | Rest]) ->
    [maps:put(Name, Type, Scope) | Rest].

env_has(Name, Env) ->
    case env_find(Name, Env) of
        {ok, _Type} -> true;
        error -> false
    end.

env_find(_Name, []) ->
    error;
env_find(Name, [Scope | Rest]) ->
    case maps:find(Name, Scope) of
        {ok, Type} -> {ok, Type};
        error -> env_find(Name, Rest)
    end.

first_missing_return([]) ->
    none;
first_missing_return([#{statements := Statements} = Function | Rest]) ->
    case statements_definitely_return(Statements) of
        true -> first_missing_return(Rest);
        false -> Function
    end.

statements_definitely_return([]) ->
    false;
statements_definitely_return([Statement | Rest]) ->
    case statement_definitely_returns(Statement) of
        true -> true;
        false -> statements_definitely_return(Rest)
    end.

statement_definitely_returns(#{kind := return}) ->
    true;
statement_definitely_returns(#{kind := 'if', branches := Branches,
                               else_branch := Else}) ->
    Else =/= none andalso
    all_statement_groups_return([maps:get(statements, Branch) || Branch <- Branches]) andalso
    statements_definitely_return(Else);
statement_definitely_returns(#{kind := unless, statements := Statements,
                               else_branch := Else}) ->
    Else =/= none andalso
    statements_definitely_return(Statements) andalso
    statements_definitely_return(Else);
statement_definitely_returns(#{kind := switch, cases := Cases,
                               exhaustive := true}) ->
    all_statement_groups_return([maps:get(statements, Case) || Case <- Cases]);
statement_definitely_returns(_Statement) ->
    false.

all_statement_groups_return(Groups) ->
    Groups =/= [] andalso lists:all(fun statements_definitely_return/1, Groups).

parse_bodies([], _Signatures, Acc) -> {ok, Acc};
parse_bodies([F | Rest], Signatures, Acc) ->
    Env = env_from_bindings([{maps:get(name, P), maps:get(type, P)}
                             || P <- maps:get(params, F)]),
    case parse_statements(maps:get(body, F), F, Signatures, Env, []) of
        {ok, Statements, _} ->
            parse_bodies(Rest, Signatures, [F#{statements => Statements} | Acc]);
        {error, Reason} -> {error, {in_function, maps:get(name, F), Reason}}
    end.

parse_statements([], _F, _Sigs, Env, Acc) ->
    {ok, lists:reverse(Acc), Env};
parse_statements([{id, Name}, {equals, "="} | _Rest], _F, _Sigs, Env, _Acc) ->
    case env_has(Name, Env) of
        true -> {error, {immutable_variable, Name}};
        false -> {error, {unknown_variable, Name}}
    end;
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
                    parse_statements(Remaining, F, Sigs, env_put(Name, Type, Env),
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
    parse_scoped_statement(Tokens, F, Sigs, Env, Acc);
parse_statements(Tokens, _F, _Sigs, _Env, _Acc) ->
    {error, {unsupported_statement, Tokens}}.

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
                            LoopEnv = env_put("it", int,
                                              env_put(Binding, var, env_child(Env))),
                            parse_loop_body(for_each, BodyStart, Rest, F, Sigs, Env,
                                            LoopEnv, Acc,
                                            #{binding => Binding, iterable => Iterable});
                        false -> {error, {expected_iterable, IterableType, Iterable}}
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
            LoopEnv = env_put("it", int, env_child(Env)),
            parse_loop_body('for', BodyStart, Tokens, F, Sigs, Env, LoopEnv, Acc,
                            #{iterator => Range, args => Args});
        {ok, OtherIterator, _Rest} -> {error, {expected_range_iterator, OtherIterator}};
        Error -> Error
    end.

parse_condition_loop(Kind, Tokens, F, Sigs, Env, Acc) ->
    LoopEnv = env_put("it", int, env_child(Env)),
    case parse_expr(Tokens, Sigs, LoopEnv) of
        {ok, Condition, [{lbrace, "{"} | BodyStart]} ->
            case require_bool(Condition, Sigs, LoopEnv) of
                ok ->
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
                            case parse_statements(Body, F, Sigs, env_child(Env), []) of
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
                    case parse_statements(Body, F, Sigs, env_child(Env), []) of
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
                    case parse_statements(ElseBody, F, Sigs, env_child(Env), []) of
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
parse_cases([{keyword, 'case'}, {atomprefix, ":"}, {id, Name}, {atomprefix, ":"} | BodyTokens],
            SubjectType, F, Sigs, Env, Acc, HasDefault) ->
    Pattern = {atom, list_to_atom(Name)},
    case types_compatible(SubjectType, atom) of
        true -> parse_case_body(Pattern, BodyTokens, SubjectType,
                                F, Sigs, Env, Acc, HasDefault);
        false -> {error, {case_type_mismatch, SubjectType, atom}}
    end;
parse_cases([{keyword, 'case'}, {atomprefix, ":"} | BodyTokens], SubjectType,
            F, Sigs, Env, Acc, false) ->
    parse_case_body(default, BodyTokens, SubjectType, F, Sigs, Env, Acc, true);
parse_cases([{keyword, 'case'}, {atomprefix, ":"} | _BodyTokens], _SubjectType,
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
            case parse_statements(Body, F, Sigs, env_child(Env), []) of
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
        {ok, Type} -> {error, {expected_boolean_condition, Type, Condition}};
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
                            NewEnv = lists:foldl(fun({T, N}, E) -> env_put(N, T, E) end,
                                                 Env, Bindings),
                            parse_statements(Remaining, F, Sigs, NewEnv, [Stmt | Acc]);
                        false -> {error, {return_type_mismatch, Expected, Actual}}
                    end;
                Error -> Error
            end;
        {ok, _Value, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end.

parse_scoped_statement(Tokens, F, Sigs, Env, Acc) ->
    case take_statement(Tokens, 0, []) of
        {ok, StatementTokens, Rest} ->
            case parse_scoped_declaration(StatementTokens, Sigs, Env) of
                {ok, Stmt, NewEnv} ->
                    parse_statements(Rest, F, Sigs, NewEnv, [Stmt | Acc]);
                Error -> Error
            end;
        Error -> Error
    end.

parse_scoped_declaration([{keyword, Scope}, {keyword, Type}, {id, Name},
                          {equals, "="} | ValueTokens], Sigs, Env) ->
    parse_declaration_value(Scope, runtime, Type, Name, ValueTokens, Sigs, Env);
parse_scoped_declaration([{keyword, Scope}, {keyword, Modifier}, {keyword, Type},
                          {id, Name}, {equals, "="} | ValueTokens], Sigs, Env)
  when Modifier == lazy; Modifier == const; Modifier == computed;
       Modifier == atomic; Modifier == thread_local ->
    parse_declaration_value(Scope, Modifier, Type, Name, ValueTokens, Sigs, Env);
parse_scoped_declaration([{keyword, Scope}, {lparen, "("} | Rest], Sigs, Env) ->
    case parse_parenthesized_bindings(Rest, []) of
        {ok, Bindings, [{equals, "="} | ValueTokens]} ->
            case parse_expr(ValueTokens, Sigs, Env) of
                {ok, Value, [{endofline, ";"}]} ->
                    Items = [#{type => Type, name => Name}
                             || {Type, Name} <- Bindings],
                    NewEnv = lists:foldl(
                        fun({Type, Name}, Current) -> env_put(Name, Type, Current) end,
                        Env, Bindings),
                    {ok, #{kind => multi_binding, scope => Scope, bindings => Items,
                           value => Value}, NewEnv};
                {ok, _Value, Other} -> {error, {expected_endofline, Other}};
                Error -> Error
            end;
        {ok, _Bindings, Other} -> {error, {expected_equals, Other}};
        Error -> Error
    end;
parse_scoped_declaration(Tokens, _Sigs, _Env) ->
    {error, {expected_variable_declaration, Tokens}}.

parse_declaration_value(Scope, Modifier, DeclaredType, Name, ValueTokens, Sigs, Env) ->
    case parse_expr(ValueTokens, Sigs, Env) of
        {ok, Value, [{endofline, ";"}]} ->
            case single_type(Value, Sigs, Env) of
                {ok, ActualType} ->
                    Type = case DeclaredType of
                               var -> ActualType;
                               _ -> DeclaredType
                           end,
                    case type_accepts(Type, ActualType) of
                        true ->
                             {ok, #{kind => variable, scope => Scope, eval => Modifier,
                               type => Type, name => Name, value => Value,
                               concurrency => concurrency(Modifier)},
                             env_put(Name, Type, Env)};
                        false ->
                            {error, {type_mismatch, Type, Value}}
                    end;
                Error -> Error
            end;
        {ok, _Value, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end.

parse_parenthesized_bindings([{keyword, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_parenthesized_bindings(Rest, [{Type, Name} | Acc]);
parse_parenthesized_bindings([{keyword, Type}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([{Type, Name} | Acc]), Rest};
parse_parenthesized_bindings(Other, _Acc) ->
    {error, {expected_destructure_binding, Other}}.

concurrency(atomic) -> atomic;
concurrency(thread_local) -> thread_local;
concurrency(_Modifier) -> shared.

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
parse_primary([{keyword, V} | Rest], _Sigs, _Env) when V == null; V == nil ->
    {ok, null, Rest};
parse_primary([{atomprefix, ":"}, {id, Name} | Rest], _Sigs, _Env) ->
    {ok, {atom, list_to_atom(Name)}, Rest};
parse_primary([{id, Name}, {lparen, "("} | Rest], Sigs, Env) ->
    parse_call(Name, Rest, Sigs, Env);
parse_primary([{keyword, Name}, {lparen, "("} | Rest], Sigs, Env) ->
    parse_call(Name, Rest, Sigs, Env);
parse_primary([{id, Name} | Rest], _Sigs, _Env) ->
    parse_members({var_ref, Name}, Rest);
parse_primary([{lbracket, "["} | Rest], Sigs, Env) ->
    parse_sequence(Rest, rbracket, list, [], Sigs, Env);
parse_primary([{lparen, "("} | Rest], Sigs, Env) -> parse_group(Rest, Sigs, Env);
parse_primary([{hash, "#"}, {lparen, "("} | Rest], Sigs, Env) ->
    parse_map(Rest, Sigs, Env, []);
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

parse_map([{rparen, ")"} | Rest], _Sigs, _Env, Acc) ->
    {ok, {map, lists:reverse(Acc)}, Rest};
parse_map(Tokens, Sigs, Env, Acc) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, Key, [{fat_arrow, "=>"} | ValueTokens]} ->
            case parse_expr(ValueTokens, Sigs, Env) of
                {ok, Value, [{comma, ","} | Rest]} ->
                    parse_map(Rest, Sigs, Env, [{Key, Value} | Acc]);
                {ok, Value, [{rparen, ")"} | Rest]} ->
                    {ok, {map, lists:reverse([{Key, Value} | Acc])}, Rest};
                {ok, _Value, Other} -> {error, {expected_map_separator_or_close, Other}};
                Error -> Error
            end;
        {ok, _Key, Other} -> {error, {expected_fat_arrow, Other}};
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
infer_types(null, _Sigs, _Env) -> {error, null_not_allowed};
infer_types({bool, _}, _Sigs, _Env) -> {ok, [bool]};
infer_types({atom, _}, _Sigs, _Env) -> {ok, [atom]};
infer_types({list, _}, _Sigs, _Env) -> {ok, [list]};
infer_types({tuple, _}, _Sigs, _Env) -> {ok, [tuple]};
infer_types({map, _}, _Sigs, _Env) -> {ok, [map]};
infer_types({member, Value, _Name}, Sigs, Env) ->
    case single_type(Value, Sigs, Env) of
        {ok, _Type} -> {ok, [var]};
        Error -> Error
    end;
infer_types({var_ref, Name}, _Sigs, Env) ->
    case env_find(Name, Env) of
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

add_ast_spans(Value, Span) when is_list(Value) ->
    [add_ast_spans(Item, Span) || Item <- Value];
add_ast_spans(Value, Span) when is_map(Value) ->
    WithChildren = maps:map(fun(_Key, Child) -> add_ast_spans(Child, Span) end, Value),
    case maps:is_key(kind, WithChildren) of
        true ->
            case maps:is_key(span, WithChildren) of
                true -> WithChildren;
                false -> WithChildren#{span => Span}
            end;
        false ->
            WithChildren
    end;
add_ast_spans(Value, _Span) ->
    Value.

annotate_error({error, Reason}, Tokens) ->
    {error, annotate_reason(Reason, Tokens)};
annotate_error(Other, _Tokens) ->
    Other.

annotate_reason({in_function, Name, Reason}, Tokens) ->
    {in_function, Name, annotate_reason(Reason, Tokens)};
annotate_reason(Reason, Tokens) ->
    case find_error_tokens(Reason) of
        none -> Reason;
        LegacyTokens ->
            Span = spans:from_token_sequence(Tokens, LegacyTokens),
            case Span == spans:unknown() of
                true -> Reason;
                false -> {with_span, Reason, Span}
            end
    end.

find_error_tokens(Reason) when is_tuple(Reason) ->
    find_error_tokens(tuple_to_list(Reason));
find_error_tokens(Items) when is_list(Items) ->
    case is_token_list(Items) of
        true -> Items;
        false -> find_error_tokens_in_list(Items)
    end;
find_error_tokens(_Reason) ->
    none.

find_error_tokens_in_list([]) ->
    none;
find_error_tokens_in_list([Item | Rest]) ->
    case find_error_tokens(Item) of
        none -> find_error_tokens_in_list(Rest);
        Tokens -> Tokens
    end.

is_token_list([]) ->
    false;
is_token_list(Tokens) ->
    lists:all(fun is_token/1, Tokens).

is_token({Kind, _Value}) when is_atom(Kind) ->
    true;
is_token(_Value) ->
    false.
