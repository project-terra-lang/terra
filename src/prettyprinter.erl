-module(prettyprinter).
-export([print_file/1, format_file/1, format_program/1, write_formatted_file/1,
         check_formatted_file/1]).

-define(INDENT, 4).

format_file(Path) ->
    case program:parse_file(Path) of
        {ok, Program} ->
            {ok, iolist_to_binary(format_program(Program))};
        Error ->
            Error
    end.

write_formatted_file(Path) ->
    case format_file(Path) of
        {ok, Formatted} ->
            case file:write_file(Path, Formatted) of
                ok -> {ok, Path};
                {error, Reason} -> {error, {write_failed, Reason}}
            end;
        Error ->
            Error
    end.

check_formatted_file(Path) ->
    case {file:read_file(Path), format_file(Path)} of
        {{ok, Source}, {ok, Source}} -> ok;
        {{ok, _Source}, {ok, _Formatted}} -> {error, not_formatted};
        {{error, Reason}, _} -> {error, {read_failed, Reason}};
        {_, Error} -> Error
    end.

format_program(Program) ->
    Sections = [format_imports(maps:get(imports, Program, [])),
                format_exports(maps:get(exports, Program, [])),
                format_externals(maps:get(externals, Program, [])),
                format_module_declarations(maps:get(module_declarations, Program, [])),
                format_records(maps:get(records, Program, [])),
                format_enums(maps:get(enums, Program, [])),
                format_functions(maps:get(functions, Program, []))],
    join_sections([Section || Section <- Sections, Section =/= []]).

format_imports(Imports) ->
    [["import ", maps:get(name, Import), ";\n"] || Import <- Imports].

format_exports(Exports) ->
    [["export ", Export, ";\n"] || Export <- Exports].

format_externals(Externals) ->
    [["extern ", format_return_types(maps:get(return_types, External)), " erlang.",
      maps:get(module, External), ".", maps:get(function, External), "(",
      join_comma([format_param(Param) || Param <- maps:get(params, External, [])]),
      ");\n"] || External <- Externals].

format_module_declarations(Declarations) ->
    [format_variable(Declaration, 0) || Declaration <- Declarations].

format_records(Records) ->
    [["struct ", maps:get(name, Record), " {\n",
      [indent(1), format_param(Field), ";\n"
       || Field <- maps:get(fields, Record, [])],
      "}\n"] || Record <- Records].

format_enums(Enums) ->
    [["enum ", maps:get(name, Enum), " {\n",
      [format_variant(Variant) || Variant <- maps:get(variants, Enum, [])],
      "}\n"] || Enum <- Enums].

format_variant(Variant) ->
    [indent(1), "variant ", maps:get(name, Variant), "(",
     join_comma([format_param(Field) || Field <- maps:get(fields, Variant, [])]),
     ");\n"].

format_functions(Functions) ->
    [format_function(Function) || Function <- Functions].

format_function(Function) ->
    ["function ", format_return_types(maps:get(return_types, Function)), " ",
     maps:get(name, Function), "(",
     join_comma([format_param(Param) || Param <- maps:get(params, Function, [])]),
     ") {\n",
     format_statements(maps:get(statements, Function, []), 1),
     "}\n"].

format_param(#{name := Name, type := Type}) ->
    [format_type(Type), " ", Name].

format_return_types([Type]) ->
    format_type(Type);
format_return_types(Types) ->
    ["(", join_comma([format_type(Type) || Type <- Types]), ")"].

format_type({strict_pointer, Type}) ->
    ["strict *", format_pointer_type(Type)];
format_type(Type) ->
    format_pointer_type(Type).

format_pointer_type({pointer, Type}) ->
    ["*", format_pointer_type(Type)];
format_pointer_type({named, Name}) ->
    Name;
format_pointer_type(number) -> "Number";
format_pointer_type(int) -> "Int";
format_pointer_type(sint) -> "SInt";
format_pointer_type(float) -> "Float";
format_pointer_type(atom) -> "Atom";
format_pointer_type(bool) -> "Bool";
format_pointer_type(map) -> "Map";
format_pointer_type(restricted_map) -> "RestrictedMap";
format_pointer_type(list) -> "List";
format_pointer_type(tuple) -> "Tuple";
format_pointer_type(string) -> "String";
format_pointer_type(binary) -> "Binary";
format_pointer_type(pid) -> "PID";
format_pointer_type(reference) -> "Reference";
format_pointer_type(var) -> "Var";
format_pointer_type(state) -> "State";
format_pointer_type(Type) when is_atom(Type) ->
    atom_to_list(Type).

format_statements(Statements, Level) ->
    [format_statement(Statement, Level) || Statement <- Statements].

format_statement(#{kind := variable} = Statement, Level) ->
    format_variable(Statement, Level);
format_statement(#{kind := pointer_write, pointer := Pointer, value := Value}, Level) ->
    [indent(Level), format_expr({pointer_read, Pointer}), " = ", format_expr(Value), ";\n"];
format_statement(#{kind := call, name := Name, invocation := once}, Level) ->
    [indent(Level), Name, ";\n"];
format_statement(#{kind := call, name := Name, args := Args}, Level) ->
    [indent(Level), format_call(Name, Args), ";\n"];
format_statement(#{kind := return, values := Values}, Level) ->
    [indent(Level), "return ", join_comma([format_expr(Value) || Value <- Values]), ";\n"];
format_statement(#{kind := 'if', branches := Branches, else_branch := Else}, Level) ->
    format_if(Branches, Else, Level);
format_statement(#{kind := unless, condition := Condition, statements := Statements,
                   else_branch := Else}, Level) ->
    [indent(Level), "unless ", format_expr(Condition), " {\n",
     format_statements(Statements, Level + 1),
     indent(Level), "}", format_else(Else, Level), "\n"];
format_statement(#{kind := switch, subject := Subject, cases := Cases}, Level) ->
    [indent(Level), "if ", format_expr(Subject), " == {\n",
     [format_case(Case, Level + 1) || Case <- Cases],
     indent(Level), "}\n"];
format_statement(#{kind := for_each, binding := Binding, iterable := Iterable,
                   statements := Statements}, Level) ->
    [indent(Level), "for_each ", Binding, " in ", format_expr(Iterable), " {\n",
     format_statements(Statements, Level + 1),
     indent(Level), "}\n"];
format_statement(#{kind := for, iterator := Iterator, statements := Statements}, Level) ->
    [indent(Level), "for ", format_expr(Iterator), " {\n",
     format_statements(Statements, Level + 1),
     indent(Level), "}\n"];
format_statement(#{kind := while, condition := Condition, statements := Statements}, Level) ->
    [indent(Level), "while ", format_expr(Condition), " {\n",
     format_statements(Statements, Level + 1),
     indent(Level), "}\n"];
format_statement(#{kind := do_while, condition := Condition, statements := Statements}, Level) ->
    [indent(Level), "do_while ", format_expr(Condition), " {\n",
     format_statements(Statements, Level + 1),
     indent(Level), "}\n"].

format_variable(#{scope := Scope, type := Type, name := Name, value := Value,
                  eval := Eval, concurrency := Concurrency}, Level) ->
    Modifiers = variable_modifiers(Scope, Eval, Concurrency),
    [indent(Level), join_space(Modifiers ++ [format_type(Type), Name]), " = ",
     format_expr(Value), ";\n"].

variable_modifiers(Scope, Eval, Concurrency) ->
    ScopePart = case Scope of
                    local -> ["local"];
                    global -> ["global"];
                    const -> ["const"];
                    temp -> ["temp"];
                    _ -> [atom_to_list(Scope)]
                end,
    EvalPart = case Eval of
                   const -> ["const"];
                   lazy -> ["lazy"];
                   computed -> ["computed"];
                   _ -> []
               end,
    ConcurrencyPart = case Concurrency of
                          atomic -> ["atomic"];
                          thread_local -> ["thread_local"];
                          _ -> []
                      end,
    unique_words(ScopePart ++ EvalPart ++ ConcurrencyPart, []).

unique_words([], Acc) ->
    lists:reverse(Acc);
unique_words([Word | Rest], Acc) ->
    case lists:member(Word, Acc) of
        true -> unique_words(Rest, Acc);
        false -> unique_words(Rest, [Word | Acc])
    end.

format_if([First | Rest], Else, Level) ->
    [indent(Level), "if ", format_expr(maps:get(condition, First)), " {\n",
     format_statements(maps:get(statements, First), Level + 1),
     indent(Level), "}",
     [format_elseif(Branch, Level) || Branch <- Rest],
     format_else(Else, Level),
     "\n"].

format_elseif(Branch, Level) ->
    [" elseif ", format_expr(maps:get(condition, Branch)), " {\n",
     format_statements(maps:get(statements, Branch), Level + 1),
     indent(Level), "}"].

format_else(none, _Level) ->
    [];
format_else(Statements, Level) ->
    [" else {\n", format_statements(Statements, Level + 1), indent(Level), "}"].

format_case(#{pattern := Pattern, statements := Statements}, Level) ->
    [indent(Level), "case ", format_pattern(Pattern), ":\n",
     format_statements(Statements, Level + 1)].

format_pattern(default) ->
    [];
format_pattern({variant_pattern, EnumName, VariantName, Bindings}) ->
    [EnumName, ".", VariantName, "(",
     join_comma([format_pattern_binding(Binding) || Binding <- Bindings]), ")"];
format_pattern(Value) ->
    format_expr(Value).

format_pattern_binding(#{binding := "_"}) ->
    "_";
format_pattern_binding(#{binding := Name}) ->
    ["bind ", Name].

format_expr({int, Value}) -> integer_to_list(Value);
format_expr({sint, Value}) -> integer_to_list(Value);
format_expr({float, Value}) -> float_to_list(Value, [short]);
format_expr({string, Value}) -> quote_binary(Value);
format_expr({char, Value}) -> [$', escape_char(Value), $'];
format_expr({bool, true}) -> "true";
format_expr({bool, false}) -> "false";
format_expr({atom, Value}) -> [":", atom_to_list(Value)];
format_expr({list, Values}) ->
    ["[", join_comma([format_expr(Value) || Value <- Values]), "]"];
format_expr({tuple, Values}) ->
    ["(", join_comma([format_expr(Value) || Value <- Values]), ")"];
format_expr({map, Pairs}) ->
    ["#(", join_comma([[format_expr(Key), " => ", format_expr(Value)]
                       || {Key, Value} <- Pairs]), ")"];
format_expr({record, Name, Fields}) ->
    [Name, "(", join_comma([format_expr(Value) || {_Field, Value} <- Fields]), ")"];
format_expr({variant, EnumName, VariantName, Fields}) ->
    [EnumName, ".", VariantName, "(",
     join_comma([format_expr(Value) || {_Field, Value} <- Fields]), ")"];
format_expr({update, Base, Updates}) ->
    [format_expr(Base), "{",
     join_comma([format_update(Update) || Update <- Updates]), "}"];
format_expr({pointer_new, Value}) ->
    ["*", format_expr(Value)];
format_expr({pointer_read, Value}) ->
    [format_expr(Value), ".*"];
format_expr({var_ref, Name}) ->
    Name;
format_expr({member, Value, Name}) ->
    [format_expr(Value), ".", Name];
format_expr({unary, bang, Value}) ->
    ["!", format_expr(Value)];
format_expr({unary, minus, Value}) ->
    ["-", format_expr(Value)];
format_expr({binary, Op, Left, Right}) ->
    ["(", format_expr(Left), " ", format_operator(Op), " ", format_expr(Right), ")"];
format_expr({try_call, Name, Args}) ->
    ["try ", format_call(Name, Args)];
format_expr({pipe_call, Left, Name, Args}) ->
    [format_expr(Left), " |> ", format_call(Name, Args)];
format_expr({remote_call, ModuleName, FunctionName, Args}) ->
    [ModuleName, ".", FunctionName, "(", join_comma([format_expr(Arg) || Arg <- Args]), ")"];
format_expr({ffi_call, ModuleName, FunctionName, Args, _Returns}) ->
    ["erlang.", ModuleName, ".", FunctionName, "(",
     join_comma([format_expr(Arg) || Arg <- Args]), ")"];
format_expr({call, Name, Args}) ->
    format_call(Name, Args);
format_expr({type_spec, Type}) ->
    format_type(Type).

format_call(Name, Args) when is_list(Name) ->
    [Name, "(", join_comma([format_expr(Arg) || Arg <- Args]), ")"];
format_call(Name, Args) when is_atom(Name) ->
    [format_constructor_name(Name), "(", join_comma([format_expr(Arg) || Arg <- Args]), ")"].

format_constructor_name(restricted_map) -> "RestrictedMap";
format_constructor_name(Name) -> format_type(Name).

format_update({{field, Name}, Value}) ->
    [Name, " = ", format_expr(Value)];
format_update({{key, Key}, Value}) ->
    [format_expr(Key), " => ", format_expr(Value)].

format_operator(plus) -> "+";
format_operator(minus) -> "-";
format_operator(times) -> "*";
format_operator(div_op) -> "/";
format_operator(eq_eq) -> "==";
format_operator(not_eq) -> "!=";
format_operator(lt) -> "<";
format_operator(lt_eq) -> "<=";
format_operator(gt) -> ">";
format_operator(gt_eq) -> ">=";
format_operator(and_and) -> "&&";
format_operator(or_or) -> "||".

quote_binary(Value) ->
    [$", [escape_char(Character) || Character <- unicode:characters_to_list(Value)], $"].

escape_char($\\) -> "\\\\";
escape_char($") -> "\\\"";
escape_char($\n) -> "\\n";
escape_char($\r) -> "\\r";
escape_char($\t) -> "\\t";
escape_char(Character) -> Character.

join_sections([]) ->
    [];
join_sections([Section]) ->
    Section;
join_sections([Section | Rest]) ->
    [Section, "\n", join_sections(Rest)].

join_comma(Items) ->
    lists:join(", ", Items).

join_space(Items) ->
    lists:join(" ", Items).

indent(Level) ->
    lists:duplicate(Level * ?INDENT, $ ).

%% Dump the tokens of a .terra file, one source line per output line.
%%
%% Tokens now carry line and column spans. This printer still tokenizes one
%% line at a time because its output is intentionally grouped by source line.
print_file(Path) ->
    case first:check_file_extension(Path) of
        not_match ->
            {error, bad_extension};
        match ->
            case file:read_file(Path) of
                {error, Reason} ->
                    {error, {read_failed, Reason}};
                {ok, Binary} ->
                    Lines = binary:split(Binary, [<<"\n">>], [global]),
                    io:format("[~p,~n", [filename:basename(Path)]),
                    print_lines(Lines),
                    io:format("]~n"),
                    ok
            end
    end.

print_lines([]) ->
    ok;
print_lines([Line | Rest]) ->
    case tokenize_line(Line) of
        {ok, []}       -> ok;                       % blank line or comment only
        {ok, Tokens}   -> io:format("  ~s~n", [format_tokens(Tokens)]);
        {error, Error} -> io:format("  %% ERROR ~p in: ~ts~n", [Error, Line])
    end,
    print_lines(Rest).

%% A bad character on one line shouldn't abort the whole dump.
tokenize_line(Line) ->
    try
        {ok, tokenizer:tokenize(Line)}
    catch
        error:Reason -> {error, Reason}
    end.

format_tokens(Tokens) ->
    lists:join(", ", [io_lib:format("~p", [T]) || T <- Tokens]).
