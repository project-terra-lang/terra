#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Cases = [{"tokenizer recognizes lexical rules", fun tokenizer_rules/0},
             {"parser recognizes declarations and calls", fun parser_declaration_rules/0},
             {"parser recognizes control-flow statements", fun parser_control_rules/0},
             {"parser preserves expression precedence", fun parser_expression_rules/0},
             {"type checker rejects semantic rule violations", fun type_checker_rules/0},
             {"codegen emits Erlang for supported rules", fun codegen_rules/0}],
    Results = [run_case(Case) || Case <- Cases],
    case lists:member(fail, Results) of
        true ->
            io:format("rule coverage tests failed~n"),
            halt(1);
        false ->
            io:format("rule coverage tests passed~n"),
            ok
    end.

run_case({Name, Expect}) ->
    case Expect() of
        true ->
            io:format("ok - ~s~n", [Name]),
            pass;
        Other ->
            io:format("not ok - ~s~n  got: ~p~n", [Name, Other]),
            fail
    end.

tokenizer_rules() ->
    Keywords = "if elseif else unless case for_each for in range while do_while "
               "stdout function fn struct enum variant bind return try let global local temp lazy const "
               "computed atomic thread_local Number Int SInt Float Atom Bool Map "
               "RestrictedMap List Tuple String State Var Void void True False "
               "true false null nil _",
    KeywordValues = [Value || {keyword, Value, _Span} <- tokenizer:tokenize(bin(Keywords))],
    ExpectedKeywords = ['if', elseif, 'else', unless, 'case', for_each, 'for', 'in',
                        range, while, do_while, stdout, function, fn, struct, enum, variant,
                        bind, return, 'try',
                        'let', global, local, temp, lazy, const, computed, atomic,
                        thread_local, number, int, sint, float, atom, bool, map,
                        restricted_map, list, tuple, string, state, var, void, void,
                        true, false, true, false, null, nil, '_'],
    SymbolKinds = [Kind || {Kind, _Value, _Span} <-
        tokenizer:tokenize(<<"== != <= >= => -> && || |> :: + - * / ( ) = ; : # < > ! , . { } [ ]">>)],
    ExpectedSymbols = [eq_eq, not_eq, lt_eq, gt_eq, fat_arrow, arrow, and_and,
                       or_or, pipe_op, colon_colon, plus, minus, times, div_op,
                       lparen, rparen, equals, endofline, atomprefix, hash, lt,
                       gt, bang, comma, dot, lbrace, rbrace, lbracket, rbracket],
    LiteralTokens = tokenizer:tokenize(
        <<"// comment\n-- comment\n_name42 123 10.5 \"a\\n\\t\\r\\\"\\\\\" 'Z'">>),
    [{id, "_name42", IdSpan}, {int, 123, _}, {float, 10.5, _},
     {string, <<"a\n\t\r\"\\">>, _}, {char, $Z, _}] = LiteralTokens,
    Illegal = tokenizer_exit(<<"@">>),
    BadEscape = tokenizer_exit(<<"\"\\x\"">>),
    KeywordValues == ExpectedKeywords andalso
    SymbolKinds == ExpectedSymbols andalso
    maps:get(start, IdSpan) == #{line => 3, column => 1, offset => 22} andalso
    Illegal == {error, {illegal_character, "@"}} andalso
    BadEscape == {error, {invalid_escape, "x"}}.

parser_declaration_rules() ->
    {ok, Program} = parse_source(
        "function (String, Number) Pair(Int x, String label) {\n"
        "  return label, x;\n"
        "}\n"
        "function Int Ready() {\n"
        "  return 1;\n"
        "}\n"
        "function Number Main(String Args) {\n"
        "  local String label, Number value = Pair(1, \"one\");\n"
        "  local Tuple pair = (1, \"one\");\n"
        "  local (Int id, String name) = pair;\n"
        "  const cached = value;\n"
        "  Pair(2, \"two\");\n"
        "  Ready;\n"
        "  try Pair(3, \"three\");\n"
        "  return value;\n"
        "}\n"),
    Pair = find_function("Pair", Program),
    MainStatements = main_statements(Program),
    [Multi, Tuple, Destructure, Const, Repeated, Once, Try, Return] = MainStatements,
    maps:get(return_types, Pair) == [string, number] andalso
    maps:get(params, Pair) == [#{type => int, name => "x"},
                              #{type => string, name => "label"}] andalso
    maps:get(kind, Multi) == multi_binding andalso
    [maps:get(type, B) || B <- maps:get(bindings, Multi)] == [string, number] andalso
    maps:get(value, Tuple) == {tuple, [{int, 1}, {string, <<"one">>}]} andalso
    maps:get(kind, Destructure) == multi_binding andalso
    maps:get(eval, Const) == const andalso
    maps:get(invocation, Repeated) == repeated andalso
    maps:get(invocation, Once) == once andalso
    maps:get(propagation, Try) == 'try' andalso
    maps:get(values, Return) == [{var_ref, "value"}].

parser_control_rules() ->
    {ok, Program} = parse_source(
        "function Number Main(String Args) {\n"
        "  local List items = List(1, 2);\n"
        "  local Atom status = :ready;\n"
        "  for_each item in items { stdout(item); stdout(it); }\n"
        "  for range(2) { stdout(it); }\n"
        "  while it < 1 { stdout(it); }\n"
        "  do_while it < 0 { stdout(it); }\n"
        "  if true { stdout(\"if\"); } elseif false { stdout(\"elseif\"); } else { stdout(\"else\"); }\n"
        "  unless false { stdout(\"unless\"); } else { stdout(\"unless else\"); }\n"
        "  if status == { case :ready: stdout(\"ready\"); case: stdout(\"default\"); }\n"
        "  return 0;\n"
        "}\n"),
    Statements = main_statements(Program),
    Kinds = [maps:get(kind, Statement) || Statement <- Statements],
    If = lists:nth(7, Statements),
    Unless = lists:nth(8, Statements),
    Switch = lists:nth(9, Statements),
    Kinds == [variable, variable, for_each, 'for', while, do_while, 'if',
              unless, switch, return] andalso
    length(maps:get(branches, If)) == 2 andalso
    maps:get(else_branch, If) =/= none andalso
    maps:get(else_branch, Unless) =/= none andalso
    maps:get(exhaustive, Switch) == true andalso
    [maps:get(pattern, Case) || Case <- maps:get(cases, Switch)] ==
        [{atom, ready}, default].

parser_expression_rules() ->
    {ok, Program} = parse_source(
        "function Int Inc(Int value) { return value + 1; }\n"
        "function Int Add(Int left, Int right) { return left + right; }\n"
        "function Number Main(String Args) {\n"
        "  local computed Bool guard = !false || true && 1 + 2 * 3 == 7;\n"
        "  local Int piped = 1 |> Inc() |> Add(3);\n"
        "  local Map data = #(:name => \"Terra\", :version => 1);\n"
        "  local Int count = data.count;\n"
        "  return piped;\n"
        "}\n"),
    Statements = main_statements(Program),
    [Guard, Piped, Map, Count, _Return] = Statements,
    maps:get(value, Guard) ==
        {binary, or_or,
         {unary, bang, {bool, false}},
         {binary, and_and,
          {bool, true},
          {binary, eq_eq,
           {binary, plus, {int, 1}, {binary, times, {int, 2}, {int, 3}}},
           {int, 7}}}} andalso
    maps:get(value, Piped) ==
        {pipe_call, {pipe_call, {int, 1}, "Inc", []}, "Add", [{int, 3}]} andalso
    maps:get(value, Map) ==
        {map, [{{atom, name}, {string, <<"Terra">>}}, {{atom, version}, {int, 1}}]} andalso
    maps:get(value, Count) == {member, {var_ref, "data"}, "count"}.

type_checker_rules() ->
    Cases = [{"missing main",
              "function Number Nope(String Args) { return 0; }\n",
              missing_entry_point},
             {"invalid main signature",
              "function Int Main(String Args) { return 0; }\n",
              invalid_entry_point_signature},
             {"duplicate function",
              "function Number Main(String Args) { return 0; }\n"
              "function Number Main(String Args) { return 0; }\n",
              duplicate_entry_point},
             {"void return type",
              "function void Main(String Args) { return 0; }\n",
              void_return_type},
             {"duplicate parameter",
              "function Number Main(String Args, Int Args) { return 0; }\n",
              duplicate_variable},
             {"unknown function",
              "function Number Main(String Args) { Missing(); return 0; }\n",
              unknown_function},
             {"unknown variable",
              "function Number Main(String Args) { return value; }\n",
              unknown_variable},
             {"immutable reassignment",
              "function Number Main(String Args) { local Int x = 1; x = 2; return x; }\n",
              immutable_variable},
             {"non-bool condition",
              "function Number Main(String Args) { if 1 { return 1; } else { return 0; } }\n",
              expected_boolean_condition},
             {"non-iterable for_each",
              "function Number Main(String Args) { for_each x in 1 { stdout(x); } return 0; }\n",
              expected_iterable},
             {"bad range arity",
              "function Number Main(String Args) { for range(1, 2) { stdout(it); } return 0; }\n",
              range_arity},
             {"return type mismatch",
              "function Number Main(String Args) { return \"wrong\"; }\n",
              return_type_mismatch},
             {"missing return",
              "function Number Main(String Args) { stdout(\"missing\"); }\n",
              missing_return},
             {"unreachable statement",
              "function Number Main(String Args) { return 0; stdout(\"late\"); }\n",
              unreachable_statement},
             {"case type mismatch",
              "function Number Main(String Args) { if 1 == { case \"one\": stdout(\"bad\"); case: stdout(\"ok\"); } return 0; }\n",
              case_type_mismatch},
             {"default case position",
              "function Number Main(String Args) { if 1 == { case: stdout(\"default\"); case 1: stdout(\"late\"); } return 0; }\n",
              default_case_must_be_last},
             {"duplicate case",
              "function Number Main(String Args) { if 1 == { case 1: stdout(\"a\"); case 1: stdout(\"b\"); case: stdout(\"c\"); } return 0; }\n",
              duplicate_case},
             {"try target",
              "function Number Main(String Args) { return try 1; }\n",
              try_requires_function_call},
             {"pipe target",
              "function Number Main(String Args) { return 1 |> 2; }\n",
              pipe_requires_function_call},
             {"invalid numeric conversion",
              "function Number Main(String Args) { return Int(\"1\"); }\n",
              invalid_numeric_conversion},
             {"restricted map arity",
              "function Number Main(String Args) { local RestrictedMap x = RestrictedMap(1, Map(), Map()); return 0; }\n",
              restricted_map_arity},
             {"restricted map capacity type",
              "function Number Main(String Args) { local RestrictedMap x = RestrictedMap(\"1\"); return 0; }\n",
              invalid_restricted_map_capacity},
             {"restricted map value type",
              "function Number Main(String Args) { local RestrictedMap x = RestrictedMap(1, 1); return 0; }\n",
              invalid_restricted_map_value},
             {"restricted map overflow",
              "function Number Main(String Args) { local RestrictedMap x = RestrictedMap(1, #(:a => 1, :b => 2)); return 0; }\n",
              restricted_map_capacity_exceeded},
             {"invalid atomic type",
              "function Number Main(String Args) { local atomic String x = \"bad\"; return 0; }\n",
              invalid_atomic_type},
             {"invalid global storage",
              "function Number Main(String Args) { global computed Int x = 1; return 0; }\n",
              invalid_storage_combination},
             {"global initializer closure",
              "function Number Main(String Args) { local Int x = 1; global Int y = x; return y; }\n",
              global_initializer_not_closed}],
    lists:all(fun({Name, Source, ExpectedCode}) ->
        case parse_source(Source) of
            {error, Reason} ->
                Code = diagnostics:code(Reason),
                case Code == ExpectedCode of
                    true -> true;
                    false ->
                        io:format("~s expected ~p got ~p from ~p~n",
                                  [Name, ExpectedCode, Code, Reason]),
                        false
                end;
            Other ->
                io:format("~s expected error got ~p~n", [Name, Other]),
                false
        end
    end, Cases).

codegen_rules() ->
    {ok, Program} = parse_source(
        "function Int Inc(Int value) { return value + 1; }\n"
        "function (Int, String) Pair() { return 1, \"one\"; }\n"
        "function Number Main(String Args) {\n"
        "  global Int shared = 1;\n"
        "  local lazy Int delayed = Inc(1);\n"
        "  local computed Int live = delayed + 1;\n"
        "  local atomic Int counter = 1;\n"
        "  local thread_local String session = \"local\";\n"
        "  local Int id, String label = Pair();\n"
        "  local Map data = #(:name => \"Terra\", :version => 1);\n"
        "  local RestrictedMap limited = RestrictedMap(2, data);\n"
        "  local Int count = limited.count;\n"
        "  local Int tried = try Inc(count);\n"
        "  local Int piped = tried |> Inc();\n"
        "  stdout(counter);\n"
        "  stdout(label);\n"
        "  for range(1) { stdout(it); }\n"
        "  for_each item in limited.members { stdout(item); }\n"
        "  while false { stdout(it); }\n"
        "  do_while false { stdout(it); }\n"
        "  if true { stdout(\"if\"); } else { stdout(\"else\"); }\n"
        "  unless false { stdout(\"unless\"); } else { stdout(\"unless else\"); }\n"
        "  if :ready == { case :ready: stdout(\"ready\"); case: stdout(\"default\"); }\n"
        "  return piped;\n"
        "}\n"),
    {ok, #{source := Source, passes := Passes}} =
        transpiler:codegen_pass(#{module => terra_rule_coverage, program => Program}),
    Erlang = iolist_to_binary(Source),
    Fragments = [<<"-module(terra_rule_coverage).">>,
                 <<"terra_fn_main">>,
                 <<"terra_global(\"shared\"">>,
                 <<"fun() -> terra_fn_inc(1) end">>,
                 <<"terra_atomic(1)">>,
                 <<"atomics:get(">>,
                 <<"terra_thread_local({\"Main\",\"session\"">>,
                 <<"{Terra_id_">>,
                 <<"#{name => <<\"Terra\">>, version => 1}">>,
                 <<"terra_restricted_map(2, Terra_data_">>,
                 <<"terra_member(Terra_limited_">>,
                 <<"terra_try(fun() -> terra_fn_inc(">>,
                 <<"terra_pipe(fun() -> Terra_tried_">>,
                 <<"terra_stdout([Terra_label_">>,
                 <<"terra_for_range(1">>,
                 <<"terra_for_each(terra_member(">>,
                 <<"terra_while(fun(Terra_it_">>,
                 <<"terra_do_while(fun(Terra_it_">>,
                 <<"case true of">>,
                 <<"case false of">>,
                 <<"case ready of">>],
    Passes == [parsing, name_resolution, type_checking, unreachable_code,
               definite_return, warning_analysis, lowering, codegen] andalso
    all_fragments_present(Erlang, Fragments).

parse_source(Source) ->
    program:parse(tokenizer:tokenize(bin(Source))).

main_statements(Program) ->
    maps:get(statements, find_function("Main", Program)).

find_function(Name, #{functions := Functions}) ->
    [Function] = [F || F <- Functions, maps:get(name, F) == Name],
    Function.

bin(Source) ->
    iolist_to_binary(Source).

contains(Text, Needle) ->
    case string:find(Text, Needle) of
        nomatch -> false;
        _ -> true
    end.

all_fragments_present(_Text, []) ->
    true;
all_fragments_present(Text, [Fragment | Rest]) ->
    case contains(Text, Fragment) of
        true ->
            all_fragments_present(Text, Rest);
        false ->
            io:format("missing codegen fragment: ~p~n", [Fragment]),
            false
    end.

tokenizer_exit(Source) ->
    try
        tokenizer:tokenize(Source),
        ok
    catch
        error:Reason -> {error, Reason}
    end.
