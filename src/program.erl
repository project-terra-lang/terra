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
        {ok, Tokens} ->
            case parse(Tokens) of
                {ok, Program} -> {ok, Program#{source_path => Path}};
                Error -> Error
            end;
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
     {unreachable_code, fun unreachable_code_pass/1},
     {definite_return, fun definite_return_pass/1},
     {warning_analysis, fun warning_analysis_pass/1},
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
    case extract_region_config(Tokens) of
        {ok, RegionConfig, RemainingTokens} ->
            case parse_module_items(RemainingTokens, [], [], [], []) of
                {ok, ModuleDeclarations, Records, Enums, Functions} ->
                    {ok, Context#{module_declaration_tokens => ModuleDeclarations,
                                  records => Records,
                                  enums => Enums,
                                  functions => Functions,
                                  region_config => RegionConfig}};
                Error -> Error
            end;
        Error -> Error
    end.

extract_region_config([{keyword, temp}, {keyword, region}, {lparen, "("},
                       {int, Capacity}, {rparen, ")"}, {endofline, ";"} | Rest]) ->
    {ok, {fixed, Capacity}, Rest};
extract_region_config(Tokens) ->
    {ok, auto, Tokens}.

name_resolution_pass(#{records := Records, enums := Enums,
                       functions := Functions} = Context) ->
    case duplicate_name(Functions, []) of
        none ->
            case validate_user_types(Records, Enums, Functions) of
                ok -> case validate_main_function(Functions) of
                ok -> {ok, Context#{entry => "Main",
                                    signatures => signatures(Functions, Records, Enums)}};
                Error -> Error
                end;
                Error -> Error
            end;
        "Main" -> {error, duplicate_entry_point};
        Name -> {error, {duplicate_function, Name}}
    end.

type_checking_pass(#{module_declaration_tokens := ModuleDeclarationTokens,
                     records := Records, enums := Enums, functions := Functions,
                     signatures := Signatures,
                     entry := Entry} = Context) ->
    case parse_module_declarations(ModuleDeclarationTokens, Signatures) of
        {ok, ModuleDeclarations, ModuleEnv} ->
            type_check_functions(Functions, Records, Enums, Signatures, Entry, ModuleDeclarations,
                                 ModuleEnv, Context);
        Error -> Error
    end.

type_check_functions(Functions, Records, Enums, Signatures, Entry,
                     ModuleDeclarations, ModuleEnv, Context) ->
    case parse_bodies(Functions, Signatures, ModuleEnv, []) of
        {ok, Parsed} ->
            ParsedFunctions = lists:reverse(Parsed),
            Program0 = #{kind => program, entry => Entry,
                         records => Records,
                         enums => Enums,
                         module_declarations => ModuleDeclarations,
                         functions => ParsedFunctions},
            RegionCapacity = case maps:get(region_config, Context, auto) of
                                 auto -> {auto, count_pointer_allocations(Program0)};
                                 Fixed -> Fixed
                             end,
            Program = Program0#{region_capacity => RegionCapacity},
            case duplicate_global_name(Program) of
                none ->
                    {ok, Context#{program => Program}};
                Name -> {error, {duplicate_global, Name}}
            end;
        Error -> Error
    end.

duplicate_global_name(Program) ->
    duplicate_name([#{name => Name} || Name <- global_names(Program)], []).

global_names(#{kind := variable, scope := Scope, name := Name} = Statement)
  when Scope == global; Scope == const ->
    [Name | lists:append([global_names(Value)
                         || Value <- maps:values(maps:remove(name, Statement))])];
global_names(#{kind := multi_binding, scope := Scope, bindings := Bindings,
               value := Value}) ->
    case Scope == global orelse Scope == const of
        true -> [maps:get(name, Binding) || Binding <- Bindings] ++ global_names(Value);
        false -> global_names(Value)
    end;
global_names(Value) when is_map(Value) ->
    lists:append([global_names(Child) || Child <- maps:values(Value)]);
global_names(Value) when is_list(Value) ->
    lists:append([global_names(Child) || Child <- Value]);
global_names(_Value) -> [].

unreachable_code_pass(#{program := #{functions := Functions}} = Context) ->
    case first_unreachable_statement(Functions) of
        none -> {ok, Context};
        #{function := Name, statement := Statement} ->
            {error, {in_function, Name,
                     {unreachable_statement, maps:get(kind, Statement)}}}
    end.

definite_return_pass(#{program := #{functions := Functions}} = Context) ->
    case first_missing_return(Functions) of
        none -> {ok, Context};
        #{name := Name, return_types := ReturnTypes} ->
            {error, {in_function, Name, {missing_return, ReturnTypes}}}
    end.

warning_analysis_pass(#{program := Program} = Context) ->
    {ok, Context#{program => Program#{warnings => warnings:analyze(Program)}}}.

lowering_pass(#{program := Program, source_span := SourceSpan, tokens := Tokens,
                completed_passes := Completed} = Context) ->
    Passes = lists:reverse([lowering | Completed]),
    Located = add_function_locations(Program, Tokens),
    Lowered = (add_ast_spans(Located, SourceSpan))#{passes => Passes},
    {ok, Context#{program => Lowered}}.

add_function_locations(#{functions := Functions} = Program, Tokens) ->
    {Located, _Rest} = locate_functions(Functions, Tokens, []),
    Program#{functions => Located}.

locate_functions([], Tokens, Acc) -> {lists:reverse(Acc), Tokens};
locate_functions([Function | Rest], Tokens, Acc) ->
    Name = maps:get(name, Function),
    case find_function_token(Name, Tokens) of
        {ok, Span, Remaining} ->
            Start = maps:get(start, Span),
            Located = Function#{source_line => maps:get(line, Start), span => Span},
            locate_functions(Rest, Remaining, [Located | Acc]);
        not_found ->
            locate_functions(Rest, Tokens, [Function | Acc])
    end.

find_function_token(_Name, []) -> not_found;
find_function_token(Name, [{keyword, function, Span} | Rest]) ->
    case find_function_name(Name, Rest) of
        {ok, Remaining} -> {ok, Span, Remaining};
        not_found -> find_function_token(Name, Rest)
    end;
find_function_token(Name, [_Token | Rest]) -> find_function_token(Name, Rest).

find_function_name(_Name, []) -> not_found;
find_function_name(Name, [{id, Name, _Span} | Rest]) -> {ok, Rest};
find_function_name(_Name, [{lbrace, _Value, _Span} | _Rest]) -> not_found;
find_function_name(Name, [_Token | Rest]) -> find_function_name(Name, Rest).

parse_module_items([], Declarations, Records, Enums, Functions) ->
    {ok, lists:reverse(Declarations), lists:reverse(Records),
     lists:reverse(Enums), lists:reverse(Functions)};
parse_module_items([{keyword, struct}, {id, Name}, {lbrace, "{"} | Rest],
                   Declarations, Records, Enums, Functions) ->
    case parse_record_body(Rest, [], [], []) of
        {ok, Fields, NestedRecords, NestedEnums, Remaining} ->
            Record = #{kind => struct, name => Name, fields => Fields},
            parse_module_items(Remaining, Declarations,
                               add_user_types([Record | NestedRecords], Records),
                               add_user_types(NestedEnums, Enums), Functions);
        Error -> Error
    end;
parse_module_items([{keyword, enum}, {id, Name}, {lbrace, "{"} | Rest],
                   Declarations, Records, Enums, Functions) ->
    case parse_enum_body(Rest, [], [], []) of
        {ok, Variants, NestedRecords, NestedEnums, Remaining} ->
            Enum = #{kind => enum, name => Name, variants => Variants},
            parse_module_items(Remaining, Declarations,
                               add_user_types(NestedRecords, Records),
                               add_user_types([Enum | NestedEnums], Enums), Functions);
        Error -> Error
    end;
parse_module_items([{keyword, function} | Rest], Declarations, Records, Enums, Functions) ->
    case parse_return_types(Rest) of
        {ok, Types, [{id, Name}, {lparen, "("} | ParamTokens]} ->
            case parse_function(Name, Types, ParamTokens) of
                {ok, Function, Remaining} ->
                    parse_module_items(Remaining, Declarations, Records, Enums,
                                       [Function | Functions]);
                Error -> Error
            end;
        {ok, _Types, Other} -> {error, {expected_function_name, Other}};
        Error -> Error
    end;
parse_module_items([{keyword, global} | _] = Tokens, Declarations, Records, Enums, Functions) ->
    parse_module_declaration_tokens(Tokens, Declarations, Records, Enums, Functions);
parse_module_items([{keyword, const} | _] = Tokens, Declarations, Records, Enums, Functions) ->
    parse_module_declaration_tokens(Tokens, Declarations, Records, Enums, Functions);
parse_module_items([{keyword, Scope} | _] = Tokens,
                   _Declarations, _Records, _Enums, _Functions)
  when Scope == local; Scope == temp ->
    {error, {variable_requires_scope, Scope, Tokens}};
parse_module_items(Other, _Declarations, _Records, _Enums, _Functions) ->
    {error, {expected_function_declaration, Other}}.

add_user_types(Types, Acc) ->
    lists:reverse(Types) ++ Acc.

parse_module_declaration_tokens(Tokens, Declarations, Records, Enums, Functions) ->
    case take_statement(Tokens, 0, []) of
        {ok, Declaration, Rest} ->
            parse_module_items(Rest, [Declaration | Declarations], Records, Enums, Functions);
        Error -> Error
    end.

parse_record_body([{rbrace, "}"} | Rest], FieldAcc, RecordAcc, EnumAcc) ->
    Fields = lists:reverse(FieldAcc),
    case duplicate_name(Fields, []) of
        none -> {ok, Fields, lists:reverse(RecordAcc), lists:reverse(EnumAcc), Rest};
        Name -> {error, {duplicate_record_field, Name}}
    end;
parse_record_body([{keyword, struct}, {id, Name}, {lbrace, "{"} | Rest],
                  FieldAcc, RecordAcc, EnumAcc) ->
    case parse_record_body(Rest, [], [], []) of
        {ok, Fields, NestedRecords, NestedEnums, Remaining} ->
            Record = #{kind => struct, name => Name, fields => Fields},
            parse_record_body(Remaining, FieldAcc,
                              add_user_types([Record | NestedRecords], RecordAcc),
                              add_user_types(NestedEnums, EnumAcc));
        Error -> Error
    end;
parse_record_body([{keyword, enum}, {id, Name}, {lbrace, "{"} | Rest],
                  FieldAcc, RecordAcc, EnumAcc) ->
    case parse_enum_body(Rest, [], [], []) of
        {ok, Variants, NestedRecords, NestedEnums, Remaining} ->
            Enum = #{kind => enum, name => Name, variants => Variants},
            parse_record_body(Remaining, FieldAcc,
                              add_user_types(NestedRecords, RecordAcc),
                              add_user_types([Enum | NestedEnums], EnumAcc));
        Error -> Error
    end;
parse_record_body([{keyword, Type}, {id, Name}, {endofline, ";"} | Rest],
                  FieldAcc, RecordAcc, EnumAcc) ->
    case is_type(Type) of
        true -> parse_record_body(Rest, [#{type => Type, name => Name} | FieldAcc],
                                  RecordAcc, EnumAcc);
        false -> {error, {unknown_record_field_type, Type}}
    end;
parse_record_body([{id, Type}, {id, Name}, {endofline, ";"} | Rest],
                  FieldAcc, RecordAcc, EnumAcc) ->
    parse_record_body(Rest, [#{type => {named, Type}, name => Name} | FieldAcc],
                      RecordAcc, EnumAcc);
parse_record_body([{times, "*"}, {keyword, Type}, {id, Name},
                   {endofline, ";"} | Rest], FieldAcc, RecordAcc, EnumAcc) ->
    case is_type(Type) of
        true -> parse_record_body(Rest, [#{type => {pointer, Type}, name => Name} | FieldAcc],
                                  RecordAcc, EnumAcc);
        false -> {error, {unknown_record_field_type, Type}}
    end;
parse_record_body([{times, "*"}, {id, Type}, {id, Name},
                   {endofline, ";"} | Rest], FieldAcc, RecordAcc, EnumAcc) ->
    parse_record_body(Rest, [#{type => {pointer, {named, Type}}, name => Name} | FieldAcc],
                      RecordAcc, EnumAcc);
parse_record_body([], _FieldAcc, _RecordAcc, _EnumAcc) ->
    {error, unterminated_record_body};
parse_record_body(Other, _FieldAcc, _RecordAcc, _EnumAcc) ->
    {error, {expected_record_field, Other}}.

parse_enum_body([{rbrace, "}"} | Rest], VariantAcc, RecordAcc, EnumAcc) ->
    Variants = lists:reverse(VariantAcc),
    case duplicate_name(Variants, []) of
        none -> {ok, Variants, lists:reverse(RecordAcc), lists:reverse(EnumAcc), Rest};
        Name -> {error, {duplicate_enum_variant, Name}}
    end;
parse_enum_body([{keyword, struct}, {id, Name}, {lbrace, "{"} | Rest],
                VariantAcc, RecordAcc, EnumAcc) ->
    case parse_record_body(Rest, [], [], []) of
        {ok, Fields, NestedRecords, NestedEnums, Remaining} ->
            Record = #{kind => struct, name => Name, fields => Fields},
            parse_enum_body(Remaining, VariantAcc,
                            add_user_types([Record | NestedRecords], RecordAcc),
                            add_user_types(NestedEnums, EnumAcc));
        Error -> Error
    end;
parse_enum_body([{keyword, enum}, {id, Name}, {lbrace, "{"} | Rest],
                VariantAcc, RecordAcc, EnumAcc) ->
    case parse_enum_body(Rest, [], [], []) of
        {ok, Variants, NestedRecords, NestedEnums, Remaining} ->
            Enum = #{kind => enum, name => Name, variants => Variants},
            parse_enum_body(Remaining, VariantAcc,
                            add_user_types(NestedRecords, RecordAcc),
                            add_user_types([Enum | NestedEnums], EnumAcc));
        Error -> Error
    end;
parse_enum_body([{keyword, variant} | Rest], VariantAcc, RecordAcc, EnumAcc) ->
    parse_enum_variant(Rest, VariantAcc, RecordAcc, EnumAcc);
parse_enum_body([{id, _Name} | _] = Tokens, VariantAcc, RecordAcc, EnumAcc) ->
    parse_enum_variant(Tokens, VariantAcc, RecordAcc, EnumAcc);
parse_enum_body([], _VariantAcc, _RecordAcc, _EnumAcc) ->
    {error, unterminated_enum_body};
parse_enum_body(Other, _VariantAcc, _RecordAcc, _EnumAcc) ->
    {error, {expected_enum_variant, Other}}.

parse_enum_variant([{id, Name}, {endofline, ";"} | Rest],
                   VariantAcc, RecordAcc, EnumAcc) ->
    parse_enum_body(Rest, [#{name => Name, fields => []} | VariantAcc],
                    RecordAcc, EnumAcc);
parse_enum_variant([{id, Name}, {lparen, "("} | Rest],
                   VariantAcc, RecordAcc, EnumAcc) ->
    case parse_parameters(Rest, []) of
        {ok, Fields, [{endofline, ";"} | Remaining]} ->
            case duplicate_name(Fields, []) of
                none -> parse_enum_body(Remaining,
                                        [#{name => Name, fields => Fields} | VariantAcc],
                                        RecordAcc, EnumAcc);
                Field -> {error, {duplicate_variant_field, Name, Field}}
            end;
        {ok, _Fields, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end;
parse_enum_variant(Other, _VariantAcc, _RecordAcc, _EnumAcc) ->
    {error, {expected_enum_variant, Other}}.

parse_function(Name, Types, Tokens) ->
    case parse_parameters(Tokens, []) of
        {ok, Params, [{lbrace, "{"} | BodyTokens]} ->
            case duplicate_param_name(Params) of
                none ->
                    case take_body(BodyTokens, 1, []) of
                        {ok, Body, Rest} ->
                            Function = #{kind => function, name => Name, params => Params,
                                         return_type => return_type(Types),
                                         return_types => Types, body => Body},
                            {ok, Function, Rest};
                        Error -> Error
                    end;
                Duplicate ->
                    {error, {duplicate_variable, Duplicate}}
            end;
        {ok, _Params, Other} -> {error, {expected_function_body, Other}};
        Error -> Error
    end.

duplicate_param_name(Params) ->
    duplicate_name([#{name => maps:get(name, Param)} || Param <- Params], []).

duplicate_binding_name(Bindings) ->
    duplicate_name([#{name => Name} || {_Type, Name} <- Bindings], []).

validate_binding_names(Bindings) ->
    case duplicate_binding_name(Bindings) of
        none -> ok;
        Name -> {error, {duplicate_variable, Name}}
    end.

validate_loop_binding_name("it") ->
    {error, {invalid_shadowing, "it"}};
validate_loop_binding_name(_Name) ->
    ok.

parse_return_types([{keyword, Type} | Rest]) ->
    checked_type(Type, [Type], Rest, unknown_return_type);
parse_return_types([{id, Name}, {id, _FunctionName} | _] = Tokens) ->
    [_TypeToken | Rest] = Tokens,
    {ok, [{named, Name}], Rest};
parse_return_types([{lparen, "("} | Rest]) ->
    parse_type_list(Rest, []);
parse_return_types([{times, "*"}, {keyword, Type} | Rest]) ->
    checked_type(Type, [{pointer, Type}], Rest, unknown_return_type);
parse_return_types([{times, "*"}, {id, Name} | Rest]) ->
    {ok, [{pointer, {named, Name}}], Rest};
parse_return_types(Other) ->
    {error, {expected_return_type, Other}}.

parse_type_list([{keyword, Type}, {comma, ","} | Rest], Acc) ->
    case is_type(Type) of
        true -> parse_type_list(Rest, [Type | Acc]);
        false -> {error, {unknown_return_type, Type}}
    end;
parse_type_list([{keyword, Type}, {rparen, ")"} | Rest], Acc) ->
    checked_type(Type, lists:reverse([Type | Acc]), Rest, unknown_return_type);
parse_type_list([{id, Name}, {comma, ","} | Rest], Acc) ->
    parse_type_list(Rest, [{named, Name} | Acc]);
parse_type_list([{id, Name}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([{named, Name} | Acc]), Rest};
parse_type_list([{times, "*"}, {keyword, Type}, {comma, ","} | Rest], Acc) ->
    case is_type(Type) of
        true -> parse_type_list(Rest, [{pointer, Type} | Acc]);
        false -> {error, {unknown_return_type, Type}}
    end;
parse_type_list([{times, "*"}, {keyword, Type}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([{pointer, Type} | Acc]), Rest};
parse_type_list([{times, "*"}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_type_list(Rest, [{pointer, {named, Name}} | Acc]);
parse_type_list([{times, "*"}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([{pointer, {named, Name}} | Acc]), Rest};
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
parse_parameters([{id, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_parameters(Rest, [#{type => {named, Type}, name => Name} | Acc]);
parse_parameters([{id, Type}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([#{type => {named, Type}, name => Name} | Acc]), Rest};
parse_parameters([{times, "*"}, {keyword, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    case is_type(Type) of
        true -> parse_parameters(Rest, [#{type => {pointer, Type}, name => Name} | Acc]);
        false -> {error, {unknown_parameter_type, Type}}
    end;
parse_parameters([{times, "*"}, {keyword, Type}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([#{type => {pointer, Type}, name => Name} | Acc]), Rest};
parse_parameters([{times, "*"}, {id, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_parameters(Rest, [#{type => {pointer, {named, Type}}, name => Name} | Acc]);
parse_parameters([{times, "*"}, {id, Type}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([#{type => {pointer, {named, Type}}, name => Name} | Acc]), Rest};
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

signatures(Functions, Records, Enums) ->
    FunctionSignatures =
        [{maps:get(name, F), #{kind => function, params => maps:get(params, F),
                              return_types => maps:get(return_types, F)}} || F <- Functions],
    RecordSignatures =
        [{maps:get(name, R), #{kind => struct, params => maps:get(fields, R),
                              fields => maps:get(fields, R),
                              return_types => [{named, maps:get(name, R)}]}} || R <- Records],
    EnumSignatures =
        [{maps:get(name, E), #{kind => enum, variants => maps:get(variants, E),
                              return_types => [{named, maps:get(name, E)}]}} || E <- Enums],
    maps:from_list(FunctionSignatures ++ RecordSignatures ++ EnumSignatures).

validate_user_types(Records, Enums, Functions) ->
    UserTypes = Records ++ Enums,
    case duplicate_name(UserTypes, []) of
        none ->
            FunctionNames = [maps:get(name, F) || F <- Functions],
            case [maps:get(name, T) || T <- UserTypes,
                  lists:member(maps:get(name, T), FunctionNames)] of
                [Name | _] -> {error, {duplicate_definition, Name}};
                [] -> validate_declared_types(Records, Enums, Functions)
            end;
        Name -> {error, {duplicate_user_type, Name}}
    end.

validate_declared_types(Records, Enums, Functions) ->
    Names = [maps:get(name, T) || T <- Records ++ Enums],
    Types = [maps:get(type, Field) || R <- Records, Field <- maps:get(fields, R)] ++
            [maps:get(type, Field) || E <- Enums, V <- maps:get(variants, E),
                                      Field <- maps:get(fields, V)] ++
            [Type || F <- Functions,
                     Type <- maps:get(return_types, F) ++
                             [maps:get(type, P) || P <- maps:get(params, F)]],
    ReferencedNames = lists:append([named_type_names(Type) || Type <- Types]),
    case [Name || Name <- ReferencedNames, not lists:member(Name, Names)] of
        [Name | _] -> {error, {unknown_user_type, Name}};
        [] -> ok
    end.

named_type_names({named, Name}) -> [Name];
named_type_names({pointer, Type}) -> named_type_names(Type);
named_type_names(_Type) -> [].

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

first_unreachable_statement([]) ->
    none;
first_unreachable_statement([#{name := Name, statements := Statements} | Rest]) ->
    case first_unreachable_in_statements(Statements) of
        none -> first_unreachable_statement(Rest);
        Statement -> #{function => Name, statement => Statement}
    end.

first_unreachable_in_statements(Statements) ->
    first_unreachable_in_statements(Statements, false).

first_unreachable_in_statements([], _PreviousReturned) ->
    none;
first_unreachable_in_statements([Statement | _Rest], true) ->
    Statement;
first_unreachable_in_statements([Statement | Rest], false) ->
    case first_unreachable_in_statement(Statement) of
        none ->
            first_unreachable_in_statements(Rest,
                                            statement_definitely_returns(Statement));
        Unreachable ->
            Unreachable
    end.

first_unreachable_in_statement(#{kind := 'if', branches := Branches,
                                 else_branch := Else}) ->
    Groups = [maps:get(statements, Branch) || Branch <- Branches] ++
        case Else of
            none -> [];
            _ -> [Else]
        end,
    first_unreachable_in_groups(Groups);
first_unreachable_in_statement(#{kind := unless, statements := Statements,
                                 else_branch := Else}) ->
    Groups = [Statements] ++
        case Else of
            none -> [];
            _ -> [Else]
        end,
    first_unreachable_in_groups(Groups);
first_unreachable_in_statement(#{kind := switch, cases := Cases}) ->
    first_unreachable_in_groups([maps:get(statements, Case) || Case <- Cases]);
first_unreachable_in_statement(#{kind := Kind, statements := Statements})
  when Kind == for_each; Kind == 'for'; Kind == while; Kind == do_while ->
    first_unreachable_in_statements(Statements);
first_unreachable_in_statement(_Statement) ->
    none.

first_unreachable_in_groups([]) ->
    none;
first_unreachable_in_groups([Statements | Rest]) ->
    case first_unreachable_in_statements(Statements) of
        none -> first_unreachable_in_groups(Rest);
        Statement -> Statement
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

parse_module_declarations(DeclarationTokens, Signatures) ->
    {ConstTokens, GlobalTokens} = partition_module_declarations(DeclarationTokens, [], []),
    parse_module_declarations(ConstTokens ++ GlobalTokens, Signatures, env_from_bindings([]), []).

partition_module_declarations([], Const, Global) ->
    {lists:reverse(Const), lists:reverse(Global)};
partition_module_declarations([[{keyword, const} | _] = Tokens | Rest], Const, Global) ->
    partition_module_declarations(Rest, [Tokens | Const], Global);
partition_module_declarations([Tokens | Rest], Const, Global) ->
    partition_module_declarations(Rest, Const, [Tokens | Global]).

parse_module_declarations([], _Signatures, Env, Acc) ->
    {ok, lists:reverse(Acc), Env};
parse_module_declarations([Tokens | Rest], Signatures, Env, Acc) ->
    case parse_module_declaration(Tokens, Signatures, Env) of
        {ok, Declaration, NewEnv} ->
            parse_module_declarations(Rest, Signatures, NewEnv, [Declaration | Acc]);
        Error -> Error
    end.

parse_module_declaration([{keyword, const}, {keyword, Type}, {id, Name},
                          {equals, "="} | ValueTokens], Signatures, Env) ->
    parse_declaration_value(const, const, Type, Name, ValueTokens, Signatures, Env);
parse_module_declaration([{keyword, const}, {id, Type}, {id, Name},
                          {equals, "="} | ValueTokens], Signatures, Env) ->
    parse_declaration_value(const, const, {named, Type}, Name, ValueTokens, Signatures, Env);
parse_module_declaration([{keyword, const}, {id, Name}, {equals, "="} | ValueTokens],
                         Signatures, Env) ->
    parse_declaration_value(const, const, var, Name, ValueTokens, Signatures, Env);
parse_module_declaration([{keyword, Scope}, {times, "*"} | _], _Signatures, _Env)
  when Scope == const; Scope == global ->
    {error, {invalid_pointer_storage, Scope, runtime}};
parse_module_declaration([{keyword, global}, {keyword, Type}, {id, Name},
                          {equals, "="} | ValueTokens], Signatures, Env) ->
    parse_module_global_value(runtime, Type, Name, ValueTokens, Signatures, Env);
parse_module_declaration([{keyword, global}, {id, Type}, {id, Name},
                          {equals, "="} | ValueTokens], Signatures, Env) ->
    parse_module_global_value(runtime, {named, Type}, Name, ValueTokens, Signatures, Env);
parse_module_declaration([{keyword, global}, {keyword, Modifier}, {keyword, Type},
                          {id, Name}, {equals, "="} | ValueTokens],
                         Signatures, Env)
  when Modifier == const; Modifier == atomic ->
    parse_module_global_value(Modifier, Type, Name, ValueTokens, Signatures, Env);
parse_module_declaration([{keyword, global}, {keyword, Modifier}, {keyword, _Type},
                          {id, _Name}, {equals, "="} | _ValueTokens],
                         _Signatures, _Env)
  when Modifier == lazy; Modifier == computed; Modifier == thread_local ->
    {error, {invalid_storage_combination, global, Modifier}};
parse_module_declaration([{keyword, Scope} | _] = Tokens, _Signatures, _Env)
  when Scope == local; Scope == temp ->
    {error, {variable_requires_scope, Scope, Tokens}};
parse_module_declaration(Tokens, _Signatures, _Env) ->
    {error, {expected_module_declaration, Tokens}}.

parse_module_global_value(Modifier, DeclaredType, Name, ValueTokens, Signatures, Env) ->
    case parse_expr(ValueTokens, Signatures, Env) of
        {ok, Value, [{endofline, ";"}]} ->
            case single_type(Value, Signatures, Env) of
                {ok, ActualType} ->
                    Type = case DeclaredType of
                               var -> ActualType;
                               _ -> DeclaredType
                           end,
                    case type_accepts(Type, ActualType) of
                        true ->
                            case validate_module_global_storage(Modifier, Type) of
                                ok ->
                                    {ok, #{kind => variable, scope => global,
                                           eval => Modifier, type => Type, name => Name,
                                           value => Value,
                                           concurrency => concurrency(Modifier)},
                                     env_put(Name, Type, Env)};
                                Error -> Error
                            end;
                        false ->
                            {error, {type_mismatch, Type, Value}}
                    end;
                Error -> Error
            end;
        {ok, _Value, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end.

validate_module_global_storage(atomic, Type) ->
    validate_atomic_type(Type);
validate_module_global_storage(_Modifier, _Type) ->
    ok.

parse_bodies([], _Signatures, _ModuleEnv, Acc) -> {ok, Acc};
parse_bodies([F | Rest], Signatures, ModuleEnv, Acc) ->
    Env = env_from_bindings([{maps:get(name, P), maps:get(type, P)}
                             || P <- maps:get(params, F)] ++ env_bindings(ModuleEnv)),
    case parse_statements(maps:get(body, F), F, Signatures, Env, []) of
        {ok, Statements, _} ->
            parse_bodies(Rest, Signatures, ModuleEnv, [F#{statements => Statements} | Acc]);
        {error, Reason} -> {error, {in_function, maps:get(name, F), Reason}}
    end.

env_bindings([Scope | _]) ->
    maps:to_list(Scope);
env_bindings([]) ->
    [].

parse_statements([], _F, _Sigs, Env, Acc) ->
    {ok, lists:reverse(Acc), Env};
parse_statements([{id, Name}, {dot, "."}, {times, "*"}, {equals, "="} | Rest],
                 F, Sigs, Env, Acc) ->
    parse_pointer_write(Name, Rest, F, Sigs, Env, Acc);
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
parse_statements([{keyword, 'try'} | _] = Tokens, F, Sigs, Env, Acc) ->
    case parse_expr(Tokens, Sigs, Env) of
        {ok, {try_call, Name, Args}, [{endofline, ";"} | Remaining]} ->
            Stmt = #{kind => call, name => Name, args => Args,
                     invocation => repeated, propagation => 'try'},
            parse_statements(Remaining, F, Sigs, Env, [Stmt | Acc]);
        {ok, _Value, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end;
parse_statements([{id, Name}, {endofline, ";"} | Rest], F, Sigs, Env, Acc) ->
    case validate_user_function(Name, [], Sigs, Env) of
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
parse_statements([{keyword, Scope}, {id, Type}, {id, Name}, {comma, ","} | Rest],
                 F, Sigs, Env, Acc)
  when Scope == global; Scope == local; Scope == temp ->
    case parse_bindings(Rest, [{{named, Type}, Name}]) of
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
    case validate_loop_binding_name(Binding) of
        ok ->
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
iterable_type(restricted_map) -> true;
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
parse_cases([{keyword, 'case'}, {id, EnumName}, {dot, "."}, {id, VariantName},
             {lparen, "("} | Rest], SubjectType, F, Sigs, Env, Acc, HasDefault) ->
    case parse_variant_pattern_args(Rest, []) of
        {ok, Args, [{atomprefix, ":"} | BodyTokens]} ->
            case validate_variant_pattern(EnumName, VariantName, Args,
                                          SubjectType, Sigs) of
                {ok, Pattern} ->
                    parse_case_body_if_unique(Pattern, BodyTokens, SubjectType,
                                              F, Sigs, Env, Acc, HasDefault);
                Error -> Error
            end;
        {ok, _Args, Other} -> {error, {expected_case_colon, Other}};
        Error -> Error
    end;
parse_cases([{keyword, 'case'}, {atomprefix, ":"}, {id, Name}, {atomprefix, ":"} | BodyTokens],
            SubjectType, F, Sigs, Env, Acc, HasDefault) ->
    Pattern = {atom, list_to_atom(Name)},
    case types_compatible(SubjectType, atom) of
        true -> parse_case_body_if_unique(Pattern, BodyTokens, SubjectType,
                                          F, Sigs, Env, Acc, HasDefault);
        false -> {error, {case_type_mismatch, SubjectType, atom}}
    end;
parse_cases([{keyword, 'case'}, {atomprefix, ":"} | BodyTokens], SubjectType,
            F, Sigs, Env, Acc, false) ->
    parse_case_body_if_unique(default, BodyTokens, SubjectType, F, Sigs, Env,
                              Acc, true);
parse_cases([{keyword, 'case'}, {atomprefix, ":"} | _BodyTokens], _SubjectType,
            _F, _Sigs, _Env, _Acc, true) ->
    {error, {duplicate_case, default}};
parse_cases([{keyword, 'case'} | Rest], SubjectType, F, Sigs, Env, Acc, HasDefault) ->
    case parse_expr(Rest, Sigs, Env) of
        {ok, Pattern, [{atomprefix, ":"} | BodyTokens]} ->
            case single_type(Pattern, Sigs, Env) of
                {ok, PatternType} ->
                    case types_compatible(SubjectType, PatternType) of
                        true -> parse_case_body_if_unique(Pattern, BodyTokens,
                                                          SubjectType, F, Sigs,
                                                          Env, Acc, HasDefault);
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

parse_variant_pattern_args([{rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse(Acc), Rest};
parse_variant_pattern_args([{keyword, bind}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_variant_pattern_args(Rest, [{bind, Name} | Acc]);
parse_variant_pattern_args([{keyword, bind}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([{bind, Name} | Acc]), Rest};
parse_variant_pattern_args([{keyword, '_'}, {comma, ","} | Rest], Acc) ->
    parse_variant_pattern_args(Rest, [ignore | Acc]);
parse_variant_pattern_args([{keyword, '_'}, {rparen, ")"} | Rest], Acc) ->
    {ok, lists:reverse([ignore | Acc]), Rest};
parse_variant_pattern_args(Other, _Acc) ->
    {error, {expected_variant_pattern_binding, Other}}.

validate_variant_pattern(EnumName, VariantName, Args, SubjectType, Sigs) ->
    case SubjectType == {named, EnumName} of
        false -> {error, {enum_pattern_type_mismatch, SubjectType, EnumName}};
        true ->
            case maps:find(EnumName, Sigs) of
                {ok, #{kind := enum, variants := Variants}} ->
                    case [Variant || Variant <- Variants,
                                     maps:get(name, Variant) == VariantName] of
                        [#{fields := Fields}] when length(Fields) == length(Args) ->
                            case duplicate_pattern_binding(Args) of
                                none ->
                                    Bindings = [variant_pattern_binding(Field, Arg)
                                                || {Field, Arg} <- lists:zip(Fields, Args)],
                                    {ok, {variant_pattern, EnumName, VariantName, Bindings}};
                                Name -> {error, {duplicate_pattern_binding, Name}}
                            end;
                        [#{fields := Fields}] ->
                            {error, {variant_pattern_arity, EnumName, VariantName,
                                     length(Fields), length(Args)}};
                        [] -> {error, {unknown_enum_variant, EnumName, VariantName}}
                    end;
                _ -> {error, {not_an_enum, EnumName}}
            end
    end.

variant_pattern_binding(Field, {bind, Name}) ->
    Field#{binding => Name};
variant_pattern_binding(Field, ignore) ->
    Field#{binding => ignore}.

duplicate_pattern_binding(Args) ->
    Names = [Name || {bind, Name} <- Args],
    duplicate_string(Names, []).

duplicate_string([], _Seen) -> none;
duplicate_string([Name | Rest], Seen) ->
    case lists:member(Name, Seen) of
        true -> Name;
        false -> duplicate_string(Rest, [Name | Seen])
    end.

parse_case_body_if_unique(Pattern, BodyTokens, SubjectType, F, Sigs, Env, Acc,
                          HasDefault) ->
    Key = pattern_key(Pattern),
    case lists:any(fun(Case) -> pattern_key(maps:get(pattern, Case)) == Key end, Acc) of
        true -> {error, {duplicate_case, Pattern}};
        false ->
            parse_case_body(Pattern, BodyTokens, SubjectType, F, Sigs, Env, Acc,
                            HasDefault)
    end.

pattern_key({variant_pattern, EnumName, VariantName, _Bindings}) ->
    {variant_pattern, EnumName, VariantName};
pattern_key(Pattern) -> Pattern.

parse_case_body(Pattern, Tokens, SubjectType, F, Sigs, Env, Acc, HasDefault) ->
    {Body, Rest} = take_case_body(Tokens, 0, []),
    case Pattern == default andalso Rest =/= [] of
        true -> {error, default_case_must_be_last};
        false ->
            case parse_statements(Body, F, Sigs, pattern_env(Pattern, Env), []) of
                {ok, Statements, _} ->
                    Case = #{pattern => Pattern, statements => Statements},
                    parse_cases(Rest, SubjectType, F, Sigs, Env,
                                [Case | Acc], HasDefault);
                Error -> Error
            end
    end.

pattern_env({variant_pattern, _EnumName, _VariantName, Bindings}, Env) ->
    lists:foldl(fun
        (#{binding := ignore}, Current) -> Current;
        (#{binding := Name, type := Type}, Current) -> env_put(Name, Type, Current)
    end, env_child(Env), Bindings);
pattern_env(_Pattern, Env) ->
    env_child(Env).

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
    case validate_binding_names(Bindings) of
        ok ->
            case lists:all(fun({T, _}) -> is_type(T) end, Bindings) of
                true -> {ok, Bindings, Rest};
                false -> {error, unknown_variable_type}
            end;
        Error -> Error
    end;
parse_bindings([{id, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_bindings(Rest, [{{named, Type}, Name} | Acc]);
parse_bindings([{id, Type}, {id, Name} | Rest], Acc) ->
    Bindings = lists:reverse([{{named, Type}, Name} | Acc]),
    case validate_binding_names(Bindings) of
        ok -> {ok, Bindings, Rest};
        Error -> Error
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
                            case validate_global_binding(Scope, Bindings, Value) of
                                ok ->
                                    Items = [#{type => Type, name => Name}
                                             || {Type, Name} <- Bindings],
                                    Stmt = #{kind => multi_binding, scope => Scope,
                                             bindings => Items, value => Value},
                                    NewEnv = lists:foldl(
                                        fun({T, N}, E) -> env_put(N, T, E) end,
                                        Env, Bindings),
                                    parse_statements(Remaining, F, Sigs, NewEnv,
                                                     [Stmt | Acc]);
                                Error -> Error
                            end;
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
parse_scoped_declaration([{keyword, Scope}, {id, Type}, {id, Name},
                          {equals, "="} | ValueTokens], Sigs, Env) ->
    parse_declaration_value(Scope, runtime, {named, Type}, Name, ValueTokens, Sigs, Env);
parse_scoped_declaration([{keyword, Scope}, {times, "*"}, {keyword, Type}, {id, Name},
                          {equals, "="} | ValueTokens], Sigs, Env) ->
    parse_pointer_declaration(Scope, runtime, Type, Name, ValueTokens, Sigs, Env);
parse_scoped_declaration([{keyword, Scope}, {times, "*"}, {id, Type}, {id, Name},
                          {equals, "="} | ValueTokens], Sigs, Env) ->
    parse_pointer_declaration(Scope, runtime, {named, Type}, Name, ValueTokens, Sigs, Env);
parse_scoped_declaration([{keyword, Scope}, {keyword, Modifier}, {keyword, Type},
                          {id, Name}, {equals, "="} | ValueTokens], Sigs, Env)
  when Modifier == lazy; Modifier == const; Modifier == computed;
       Modifier == atomic; Modifier == thread_local ->
    parse_declaration_value(Scope, Modifier, Type, Name, ValueTokens, Sigs, Env);
parse_scoped_declaration([{keyword, Scope}, {keyword, Modifier}, {times, "*"},
                          {keyword, Type}, {id, Name}, {equals, "="} | ValueTokens],
                         Sigs, Env)
  when Modifier == lazy; Modifier == const; Modifier == computed;
       Modifier == atomic; Modifier == thread_local ->
    parse_pointer_declaration(Scope, Modifier, Type, Name, ValueTokens, Sigs, Env);
parse_scoped_declaration([{keyword, Scope}, {keyword, Modifier}, {times, "*"},
                          {id, Type}, {id, Name}, {equals, "="} | ValueTokens],
                         Sigs, Env)
  when Modifier == lazy; Modifier == const; Modifier == computed;
       Modifier == atomic; Modifier == thread_local ->
    parse_pointer_declaration(Scope, Modifier, {named, Type}, Name,
                              ValueTokens, Sigs, Env);
parse_scoped_declaration([{keyword, Scope}, {lparen, "("} | Rest], Sigs, Env) ->
    case parse_parenthesized_bindings(Rest, []) of
        {ok, Bindings, [{equals, "="} | ValueTokens]} ->
            case parse_expr(ValueTokens, Sigs, Env) of
                {ok, Value, [{endofline, ";"}]} ->
                    case validate_global_binding(Scope, Bindings, Value) of
                        ok ->
                            Items = [#{type => Type, name => Name}
                                     || {Type, Name} <- Bindings],
                            NewEnv = lists:foldl(
                                fun({Type, Name}, Current) ->
                                    env_put(Name, Type, Current)
                                end, Env, Bindings),
                            {ok, #{kind => multi_binding, scope => Scope,
                                   bindings => Items, value => Value}, NewEnv};
                        Error -> Error
                    end;
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
                            case validate_storage_declaration(Scope, Modifier, Type,
                                                              Name, Value) of
                                ok ->
                                    {ok, #{kind => variable, scope => Scope,
                                      eval => Modifier, type => Type, name => Name,
                                      value => Value,
                                      concurrency => concurrency(Modifier)},
                                     env_put(Name, Type, Env)};
                                Error -> Error
                            end;
                        false ->
                            {error, {type_mismatch, Type, Value}}
                    end;
                Error -> Error
            end;
        {ok, _Value, Other} -> {error, {expected_endofline, Other}};
        Error -> Error
    end.

parse_pointer_declaration(Scope, Modifier, DeclaredType, Name, ValueTokens, Sigs, Env) ->
    case pointer_storage_allowed(Scope, Modifier) of
        ok ->
            case parse_expr(ValueTokens, Sigs, Env) of
                {ok, Value, [{endofline, ";"}]} ->
                    case single_type(Value, Sigs, Env) of
                        {ok, {pointer, ActualPointee}} ->
                            finish_pointer_declaration(Scope, Modifier, DeclaredType,
                                                       ActualPointee, Name, Value, Sigs, Env);
                        {ok, ActualType} ->
                            finish_pointer_declaration(Scope, Modifier, DeclaredType,
                                                       ActualType, Name,
                                                       {pointer_new, Value}, Sigs, Env);
                        Error -> Error
                    end;
                {ok, _Value, Other} -> {error, {expected_endofline, Other}};
                Error -> Error
            end;
        Error -> Error
    end.

finish_pointer_declaration(Scope, Modifier, DeclaredType, ActualType, Name, Value,
                           _Sigs, Env) ->
    PointeeType = case DeclaredType of var -> ActualType; _ -> DeclaredType end,
    case type_accepts(PointeeType, ActualType) of
        true ->
            PointerType = {pointer, PointeeType},
            {ok, #{kind => variable, scope => Scope, eval => Modifier,
                   type => PointerType, name => Name, value => Value,
                   concurrency => shared},
             env_put(Name, PointerType, Env)};
        false -> {error, {pointer_type_mismatch, PointeeType, ActualType}}
    end.

pointer_storage_allowed(local, runtime) -> ok;
pointer_storage_allowed(Scope, Modifier) ->
    {error, {invalid_pointer_storage, Scope, Modifier}}.

parse_pointer_write(Name, Tokens, F, Sigs, Env, Acc) ->
    case env_find(Name, Env) of
        {ok, {pointer, PointeeType}} ->
            case parse_expr(Tokens, Sigs, Env) of
                {ok, Value, [{endofline, ";"} | Remaining]} ->
                    case single_type(Value, Sigs, Env) of
                        {ok, ActualType} ->
                            case type_accepts(PointeeType, ActualType) of
                                true ->
                                    Statement = #{kind => pointer_write,
                                                  pointer => {var_ref, Name},
                                                  value => Value},
                                    parse_statements(Remaining, F, Sigs, Env,
                                                     [Statement | Acc]);
                                false ->
                                    {error, {pointer_type_mismatch,
                                             PointeeType, ActualType}}
                            end;
                        Error -> Error
                    end;
                {ok, _Value, Other} -> {error, {expected_endofline, Other}};
                Error -> Error
            end;
        {ok, Type} -> {error, {dereference_non_pointer, Type}};
        error -> {error, {unknown_variable, Name}}
    end.

parse_parenthesized_bindings([{keyword, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_parenthesized_bindings(Rest, [{Type, Name} | Acc]);
parse_parenthesized_bindings([{keyword, Type}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    Bindings = lists:reverse([{Type, Name} | Acc]),
    case validate_binding_names(Bindings) of
        ok -> {ok, Bindings, Rest};
        Error -> Error
    end;
parse_parenthesized_bindings([{id, Type}, {id, Name}, {comma, ","} | Rest], Acc) ->
    parse_parenthesized_bindings(Rest, [{{named, Type}, Name} | Acc]);
parse_parenthesized_bindings([{id, Type}, {id, Name}, {rparen, ")"} | Rest], Acc) ->
    Bindings = lists:reverse([{{named, Type}, Name} | Acc]),
    case validate_binding_names(Bindings) of
        ok -> {ok, Bindings, Rest};
        Error -> Error
    end;
parse_parenthesized_bindings(Other, _Acc) ->
    {error, {expected_destructure_binding, Other}}.

concurrency(atomic) -> atomic;
concurrency(thread_local) -> thread_local;
concurrency(_Modifier) -> shared.

validate_storage_declaration(global, thread_local, _Type, _Name, _Value) ->
    {error, {invalid_storage_combination, global, thread_local}};
validate_storage_declaration(global, computed, _Type, _Name, _Value) ->
    {error, {invalid_storage_combination, global, computed}};
validate_storage_declaration(global, lazy, _Type, _Name, _Value) ->
    {error, {invalid_storage_combination, global, lazy}};
validate_storage_declaration(global, atomic, Type, Name, Value) ->
    case validate_atomic_type(Type) of
        ok -> validate_closed_global(Name, Value);
        Error -> Error
    end;
validate_storage_declaration(global, _Modifier, _Type, Name, Value) ->
    validate_closed_global(Name, Value);
validate_storage_declaration(const, const, _Type, _Name, _Value) ->
    ok;
validate_storage_declaration(_Scope, atomic, Type, _Name, _Value) ->
    validate_atomic_type(Type);
validate_storage_declaration(_Scope, _Modifier, _Type, _Name, _Value) ->
    ok.

validate_closed_global(Name, Value) ->
    case expression_has_variable_reference(Value) of
        true -> {error, {global_initializer_not_closed, Name}};
        false -> ok
    end.

validate_global_binding(global, [{_Type, Name} | _], Value) ->
    validate_closed_global(Name, Value);
validate_global_binding(_Scope, _Bindings, _Value) -> ok.

validate_atomic_type(int) -> ok;
validate_atomic_type(sint) -> ok;
validate_atomic_type(Type) -> {error, {invalid_atomic_type, Type}}.

expression_has_variable_reference({var_ref, _Name}) -> true;
expression_has_variable_reference(Value) when is_tuple(Value) ->
    lists:any(fun expression_has_variable_reference/1, tuple_to_list(Value));
expression_has_variable_reference(Value) when is_list(Value) ->
    lists:any(fun expression_has_variable_reference/1, Value);
expression_has_variable_reference(Value) when is_map(Value) ->
    lists:any(fun expression_has_variable_reference/1, maps:values(Value));
expression_has_variable_reference(_Value) -> false.

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
    case parse_or(Tokens, Sigs, Env) of
        {ok, Left, Rest} -> parse_pipe_rest(Left, Rest, Sigs, Env);
        Error -> Error
    end.

parse_pipe_rest(Left, [{pipe_op, "|>"} | Rest], Sigs, Env) ->
    case parse_pipe_target(Rest, Sigs, Env) of
        {ok, Name, Args, Remaining} ->
            case validate_user_function(Name, [Left | Args], Sigs, Env) of
                {ok, _Types} ->
                    parse_pipe_rest({pipe_call, Left, Name, Args}, Remaining, Sigs, Env);
                Error -> Error
            end;
        Error -> Error
    end;
parse_pipe_rest(Left, Rest, _Sigs, _Env) ->
    {ok, Left, Rest}.

parse_pipe_target([{id, Name}, {lparen, "("}, {rparen, ")"} | Rest], _Sigs, _Env) ->
    {ok, Name, [], Rest};
parse_pipe_target([{id, Name}, {lparen, "("} | Rest], Sigs, Env) ->
    case parse_sequence(Rest, rparen, call_args, [], Sigs, Env) of
        {ok, {call_args, Args}, Remaining} -> {ok, Name, Args, Remaining};
        Error -> Error
    end;
parse_pipe_target(Other, _Sigs, _Env) ->
    {error, {pipe_requires_function_call, Other}}.

parse_or(Tokens, Sigs, Env) ->
    case parse_and(Tokens, Sigs, Env) of
        {ok, Left, Rest} -> parse_or_rest(Left, Rest, Sigs, Env);
        Error -> Error
    end.

parse_or_rest(Left, [{or_or, _} | Rest], Sigs, Env) ->
    case parse_and(Rest, Sigs, Env) of
        {ok, Right, Remaining} ->
            parse_or_rest({binary, or_or, Left, Right}, Remaining, Sigs, Env);
        Error -> Error
    end;
parse_or_rest(Left, Rest, _Sigs, _Env) ->
    {ok, Left, Rest}.

parse_and(Tokens, Sigs, Env) ->
    case parse_compare(Tokens, Sigs, Env) of
        {ok, Left, Rest} -> parse_and_rest(Left, Rest, Sigs, Env);
        Error -> Error
    end.

parse_and_rest(Left, [{and_and, _} | Rest], Sigs, Env) ->
    case parse_compare(Rest, Sigs, Env) of
        {ok, Right, Remaining} ->
            parse_and_rest({binary, and_and, Left, Right}, Remaining, Sigs, Env);
        Error -> Error
    end;
parse_and_rest(Left, Rest, _Sigs, _Env) ->
    {ok, Left, Rest}.

parse_compare(Tokens, Sigs, Env) ->
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
    case parse_unary(Tokens, Sigs, Env) of
        {ok, Left, Rest} -> parse_mul_rest(Left, Rest, Sigs, Env);
        Error -> Error
    end.

parse_mul_rest(Left, [{Op, _} | Rest], Sigs, Env) when Op == times; Op == div_op ->
    case parse_unary(Rest, Sigs, Env) of
        {ok, Right, Remaining} ->
            parse_mul_rest({binary, Op, Left, Right}, Remaining, Sigs, Env);
        Error -> Error
    end;
parse_mul_rest(Left, Rest, _Sigs, _Env) -> {ok, Left, Rest}.

parse_unary([{minus, "-"}, {int, V} | Rest], _Sigs, _Env) ->
    {ok, {sint, -V}, Rest};
parse_unary([{minus, "-"}, {float, V} | Rest], _Sigs, _Env) ->
    {ok, {float, -V}, Rest};
parse_unary([{minus, "-"} | Rest], Sigs, Env) ->
    case parse_unary(Rest, Sigs, Env) of
        {ok, Value, Remaining} -> {ok, {unary, minus, Value}, Remaining};
        Error -> Error
    end;
parse_unary([{bang, "!"} | Rest], Sigs, Env) ->
    case parse_unary(Rest, Sigs, Env) of
        {ok, Value, Remaining} -> {ok, {unary, bang, Value}, Remaining};
        Error -> Error
    end;
parse_unary([{keyword, 'try'} | Rest], Sigs, Env) ->
    case parse_unary(Rest, Sigs, Env) of
        {ok, {call, Name, Args}, Remaining} when is_list(Name) ->
            {ok, {try_call, Name, Args}, Remaining};
        {ok, Value, _Remaining} -> {error, {try_requires_function_call, Value}};
        Error -> Error
    end;
parse_unary([{times, "*"} | Rest], Sigs, Env) ->
    case parse_unary(Rest, Sigs, Env) of
        {ok, Value, Remaining} -> {ok, {pointer_new, Value}, Remaining};
        Error -> Error
    end;
parse_unary(Tokens, Sigs, Env) ->
    parse_primary(Tokens, Sigs, Env).

parse_primary([{int, V} | Rest], _Sigs, _Env) -> {ok, {int, V}, Rest};
parse_primary([{float, V} | Rest], _Sigs, _Env) -> {ok, {float, V}, Rest};
parse_primary([{string, V} | Rest], _Sigs, _Env) -> {ok, {string, V}, Rest};
parse_primary([{char, V} | Rest], _Sigs, _Env) -> {ok, {char, V}, Rest};
parse_primary([{keyword, V} | Rest], _Sigs, _Env) when V == true; V == false ->
    {ok, {bool, V}, Rest};
parse_primary([{keyword, V} | Rest], _Sigs, _Env) when V == null; V == nil ->
    {ok, null, Rest};
parse_primary([{atomprefix, ":"}, {id, Name} | Rest], _Sigs, _Env) ->
    {ok, {atom, list_to_atom(Name)}, Rest};
parse_primary([{id, EnumName}, {dot, "."}, {id, VariantName},
               {lparen, "("} | Rest], Sigs, Env) ->
    parse_variant_call(EnumName, VariantName, Rest, Sigs, Env);
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
parse_members(Value, [{dot, "."}, {times, "*"} | Rest]) ->
    parse_members({pointer_read, Value}, Rest);
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
        {ok, _} -> {ok, call_expression(Name, [], Sigs), Rest};
        Error -> Error
    end;
parse_call(Name, Tokens, Sigs, Env) ->
    case parse_sequence(Tokens, rparen, call_args, [], Sigs, Env) of
        {ok, {call_args, Args}, Rest} ->
            case validate_call(Name, Args, Sigs, Env) of
                {ok, _} -> {ok, call_expression(Name, Args, Sigs), Rest};
                Error -> Error
            end;
        Error -> Error
    end.

call_expression(Name, Args, Sigs) when is_list(Name) ->
    case maps:find(Name, Sigs) of
        {ok, #{kind := struct, fields := Fields}} ->
            {record, Name, lists:zip([maps:get(name, Field) || Field <- Fields], Args)};
        _ -> {call, Name, Args}
    end;
call_expression(Name, Args, _Sigs) ->
    {call, Name, Args}.

parse_variant_call(EnumName, VariantName, [{rparen, ")"} | Rest], Sigs, Env) ->
    build_variant(EnumName, VariantName, [], Rest, Sigs, Env);
parse_variant_call(EnumName, VariantName, Tokens, Sigs, Env) ->
    case parse_sequence(Tokens, rparen, call_args, [], Sigs, Env) of
        {ok, {call_args, Args}, Rest} ->
            build_variant(EnumName, VariantName, Args, Rest, Sigs, Env);
        Error -> Error
    end.

build_variant(EnumName, VariantName, Args, Rest, Sigs, Env) ->
    case maps:find(EnumName, Sigs) of
        {ok, #{kind := enum, variants := Variants}} ->
            case [Variant || Variant <- Variants,
                             maps:get(name, Variant) == VariantName] of
                [#{fields := Fields}] ->
                    Expected = [maps:get(type, Field) || Field <- Fields],
                    case expression_types(Args, Sigs, Env, []) of
                        {ok, Actual} ->
                            case types_accept(Expected, Actual) of
                                true ->
                                    Values = lists:zip(
                                        [maps:get(name, Field) || Field <- Fields], Args),
                                    {ok, {variant, EnumName, VariantName, Values}, Rest};
                                false ->
                                    {error, {variant_type_mismatch, EnumName, VariantName,
                                             Expected, Actual}}
                            end;
                        Error -> Error
                    end;
                [] -> {error, {unknown_enum_variant, EnumName, VariantName}}
            end;
        {ok, _Other} -> {error, {not_an_enum, EnumName}};
        error -> {error, {unknown_enum, EnumName}}
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
validate_call(restricted_map, Args, Sigs, Env) ->
    validate_restricted_map(Args, Sigs, Env);
validate_call(Name, Args, Sigs, Env)
  when Name == number; Name == int; Name == sint; Name == float ->
    validate_numeric_conversion(Name, Args, Sigs, Env);
validate_call(Name, Args, Sigs, Env) when is_list(Name) ->
    case maps:find(Name, Sigs) of
        {ok, #{kind := enum}} -> {error, {enum_variant_required, Name}};
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

validate_user_function(Name, Args, Sigs, Env) ->
    case maps:find(Name, Sigs) of
        {ok, #{kind := function}} -> validate_call(Name, Args, Sigs, Env);
        {ok, #{kind := Kind}} when Kind == struct; Kind == enum ->
            {error, {function_call_required, Name}};
        error -> validate_call(Name, Args, Sigs, Env)
    end.

validate_numeric_conversion(Target, [Arg], Sigs, Env) ->
    case single_type(Arg, Sigs, Env) of
        {ok, Source} ->
            case is_number_type(Source) of
                true -> {ok, [Target]};
                false -> {error, {invalid_numeric_conversion, Source, Target}}
            end;
        Error -> Error
    end;
validate_numeric_conversion(Target, Args, _Sigs, _Env) ->
    {error, {numeric_conversion_arity, Target, 1, length(Args)}}.

validate_restricted_map([Capacity], Sigs, Env) ->
    validate_restricted_map_arguments(Capacity, {map, []}, Sigs, Env);
validate_restricted_map([Capacity, Value], Sigs, Env) ->
    validate_restricted_map_arguments(Capacity, Value, Sigs, Env);
validate_restricted_map(Args, _Sigs, _Env) ->
    {error, {restricted_map_arity, length(Args)}}.

validate_restricted_map_arguments(Capacity, Value, Sigs, Env) ->
    case {single_type(Capacity, Sigs, Env), single_type(Value, Sigs, Env)} of
        {{ok, int}, {ok, map}} ->
            validate_restricted_map_literal(Capacity, Value);
        {{ok, CapacityType}, {ok, map}} ->
            {error, {invalid_restricted_map_capacity, CapacityType}};
        {{ok, int}, {ok, ValueType}} ->
            {error, {invalid_restricted_map_value, ValueType}};
        {{error, Reason}, _} -> {error, Reason};
        {_, {error, Reason}} -> {error, Reason};
        {{ok, CapacityType}, {ok, _ValueType}} ->
            {error, {invalid_restricted_map_capacity, CapacityType}}
    end.

validate_restricted_map_literal({int, Capacity}, {map, Pairs})
  when length(Pairs) > Capacity ->
    {error, {restricted_map_capacity_exceeded, Capacity, length(Pairs)}};
validate_restricted_map_literal(_Capacity, _Value) ->
    {ok, [restricted_map]}.

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
infer_types({record, Name, _Fields}, _Sigs, _Env) -> {ok, [{named, Name}]};
infer_types({variant, Name, _Variant, _Fields}, _Sigs, _Env) -> {ok, [{named, Name}]};
infer_types({pointer_new, Value}, Sigs, Env) ->
    case single_type(Value, Sigs, Env) of
        {ok, Type} -> {ok, [{pointer, Type}]};
        Error -> Error
    end;
infer_types({pointer_read, Value}, Sigs, Env) ->
    case single_type(Value, Sigs, Env) of
        {ok, {pointer, Type}} -> {ok, [Type]};
        {ok, Type} -> {error, {dereference_non_pointer, Type}};
        Error -> Error
    end;
infer_types({member, Value, Name}, Sigs, Env) ->
    case single_type(Value, Sigs, Env) of
        {ok, Type} when (Type == map orelse Type == restricted_map), Name == "count" ->
            {ok, [int]};
        {ok, Type} when (Type == map orelse Type == restricted_map), Name == "members" ->
            {ok, [list]};
        {ok, Type} when Type == map; Type == restricted_map -> {ok, [var]};
        {ok, {named, TypeName}} -> named_field_type(TypeName, Name, Sigs);
        {ok, _Type} -> {ok, [var]};
        Error -> Error
    end;
infer_types({var_ref, Name}, _Sigs, Env) ->
    case env_find(Name, Env) of
        {ok, Type} -> {ok, [Type]};
        error -> {error, {unknown_variable, Name}}
    end;
infer_types({try_call, Name, Args}, Sigs, Env) -> validate_call(Name, Args, Sigs, Env);
infer_types({pipe_call, Left, Name, Args}, Sigs, Env) ->
    validate_call(Name, [Left | Args], Sigs, Env);
infer_types({call, Name, Args}, Sigs, Env) -> validate_call(Name, Args, Sigs, Env);
infer_types({binary, Op, Left, Right}, Sigs, Env) ->
    case {single_type(Left, Sigs, Env), single_type(Right, Sigs, Env)} of
        {{ok, LT}, {ok, RT}} -> binary_type(Op, LT, RT);
        {{error, Reason}, _} -> {error, Reason};
        {_, {error, Reason}} -> {error, Reason}
    end;
infer_types({unary, Op, Value}, Sigs, Env) ->
    case single_type(Value, Sigs, Env) of
        {ok, Type} -> unary_type(Op, Type);
        {error, Reason} -> {error, Reason}
    end;
infer_types(_Expr, _Sigs, _Env) -> {error, unknown_type}.

named_field_type(TypeName, FieldName, Sigs) ->
    case maps:find(TypeName, Sigs) of
        {ok, #{kind := struct, fields := Fields}} ->
            case [maps:get(type, Field) || Field <- Fields,
                  maps:get(name, Field) == FieldName] of
                [Type] -> {ok, [Type]};
                [] -> {error, {unknown_record_field, TypeName, FieldName}}
            end;
        {ok, #{kind := enum}} when FieldName == "tag" ->
            {ok, [atom]};
        {ok, #{kind := enum, variants := Variants}} ->
            Types = lists:usort(
                [maps:get(type, Field) || Variant <- Variants,
                 Field <- maps:get(fields, Variant), maps:get(name, Field) == FieldName]),
            case Types of
                [Type] -> {ok, [Type]};
                [] -> {error, {unknown_enum_field, TypeName, FieldName}};
                _ -> {ok, [var]}
            end;
        _ -> {error, {unknown_user_type, TypeName}}
    end.

binary_type(plus, string, string) -> {ok, [string]};
binary_type(div_op, Left, Right) ->
    numeric_binary_type(div_op, Left, Right);
binary_type(Op, Left, Right) when Op == plus; Op == minus; Op == times ->
    numeric_binary_type(Op, Left, Right);
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
binary_type(Op, bool, bool) when Op == and_and; Op == or_or ->
    {ok, [bool]};
binary_type(_Op, Left, Right) -> {error, {type_mismatch, Left, Right}}.

unary_type(bang, bool) -> {ok, [bool]};
unary_type(minus, int) -> {ok, [sint]};
unary_type(minus, Type) when Type == sint; Type == float; Type == number ->
    {ok, [Type]};
unary_type(minus, Type) -> {error, {type_mismatch, number, Type}};
unary_type(_Op, Type) -> {error, {type_mismatch, unknown, Type}}.

numeric_binary_type(Op, Left, Right) ->
    case is_number_type(Left) andalso is_number_type(Right) of
        true -> {ok, [numeric_result_type(Op, Left, Right)]};
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

types_compatible(Left, Right) ->
    (is_number_type(Left) andalso is_number_type(Right)) orelse
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
type_accepts(sint, int) -> true;
type_accepts({pointer, Expected}, {pointer, Actual}) ->
    type_accepts(Expected, Actual);
type_accepts(Type, Type) -> true;
type_accepts(_, _) -> false.

is_type(state) -> true;
is_type(var) -> true;
is_type(Type) -> datatypes:is_type(Type).

count_pointer_allocations({pointer_new, Value}) ->
    1 + count_pointer_allocations(Value);
count_pointer_allocations(Value) when is_map(Value) ->
    lists:sum([count_pointer_allocations(Child) || Child <- maps:values(Value)]);
count_pointer_allocations(Value) when is_list(Value) ->
    lists:sum([count_pointer_allocations(Child) || Child <- Value]);
count_pointer_allocations(Value) when is_tuple(Value) ->
    lists:sum([count_pointer_allocations(Child) || Child <- tuple_to_list(Value)]);
count_pointer_allocations(_Value) -> 0.

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
