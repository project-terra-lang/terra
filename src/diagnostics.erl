-module(diagnostics).
-export([format/1, render/2]).

format({in_function, Name, Reason}) ->
    {Code, Message, Help} = format(Reason),
    {Code, io_lib:format("In function ~s: ~s", [Name, Message]), Help};
format({with_span, Reason, _Span}) ->
    format(Reason);
format(missing_entry_point) ->
    {missing_entry_point,
     "No Main function was found.",
     "Add: function Number Main(String Args) { ... }"};
format(duplicate_entry_point) ->
    {duplicate_entry_point,
     "More than one Main function was defined.",
     "Keep exactly one function Number Main(String Args)."};
format({duplicate_function, Name}) ->
    {duplicate_function,
     io_lib:format("Function ~s is defined more than once.", [Name]),
     "Keep one function with that name, or rename one of them."};
format({duplicate_variable, Name}) ->
    {duplicate_variable,
     io_lib:format("Variable ~s is bound more than once in the same binding.",
                   [Name]),
     "Use each variable name once in a parameter, destructuring, or multi-binding list."};
format({invalid_shadowing, Name}) ->
    {invalid_shadowing,
     io_lib:format("Variable ~s cannot shadow an implicit binding here.", [Name]),
     "Choose a different name so the implicit binding remains unambiguous."};
format({duplicate_case, Pattern}) ->
    {duplicate_case,
     io_lib:format("Switch case ~s is already handled.", [pattern_name(Pattern)]),
     "Remove the duplicate case or combine its body with the first matching case."};
format({invalid_entry_point_signature, Signature}) ->
    {invalid_entry_point_signature,
     "Main has the wrong return type, parameter, or parameter name.",
     io_lib:format("Use: ~s", [Signature])};
format(void_return_type) ->
    {void_return_type,
     "Terra does not have void functions.",
     "Declare a concrete return type and return a value on every path."};
format({unknown_function, Name}) ->
    {unknown_function,
     io_lib:format("Function ~s is not defined.", [name(Name)]),
     "Define it before checking the program, or check the spelling."};
format({unknown_variable, Name}) ->
    {unknown_variable,
     io_lib:format("Variable ~s is not available here.", [Name]),
     "Declare the variable before using it and check its scope."};
format({immutable_variable, Name}) ->
    {immutable_variable,
     io_lib:format("Variable ~s cannot be reassigned.", [Name]),
     "Terra variables are immutable; declare a new variable instead."};
format({expected_boolean_condition, Type, _Expression}) ->
    {expected_boolean_condition,
     io_lib:format("A condition must be Bool, but this is ~s.", [type_name(Type)]),
     "Use a comparison such as x < 10 or a Bool value."};
format({expected_iterable, Type, _Expression}) ->
    {expected_iterable,
     io_lib:format("for_each cannot iterate over ~s.", [type_name(Type)]),
     "Use a List, Tuple, Map, or String."};
format(non_exhaustive_switch) ->
    {non_exhaustive_switch,
     "The switch does not handle every possible value.",
     "Add a final default branch written as case:"};
format(default_case_must_be_last) ->
    {default_case_must_be_last,
     "The default case is not the final switch branch.",
     "Move case: after all cases with explicit patterns."};
format({return_type_mismatch, Expected, Actual}) ->
    {return_type_mismatch,
     io_lib:format("Expected return values ~s, but received ~s.",
                   [type_list(Expected), type_list(Actual)]),
     "Return and assign the same number of values in the declared type order."};
format({missing_return, ReturnTypes}) ->
    {missing_return,
     io_lib:format("This function must return ~s on every path.",
                   [type_list(ReturnTypes)]),
     "Add an explicit return, or make every if/unless/switch branch return."};
format({unreachable_statement, Kind}) ->
    {unreachable_statement,
     io_lib:format("A ~s statement appears after a guaranteed return.",
                   [statement_name(Kind)]),
     "Remove the unreachable statement or move it before the return."};
format({argument_type_mismatch, Name, Expected, Actual}) ->
    {argument_type_mismatch,
     io_lib:format("Call to ~s expects ~s, but received ~s.",
                   [name(Name), type_list(Expected), type_list(Actual)]),
     "Check the function signature and argument order."};
format({case_type_mismatch, Expected, Actual}) ->
    {case_type_mismatch,
     io_lib:format("Switch value is ~s, but this case is ~s.",
                   [type_name(Expected), type_name(Actual)]),
     "Use a case pattern compatible with the switched value."};
format({expected_range_number, Type}) ->
    {expected_range_number,
     io_lib:format("range expects a Number, but received ~s.", [type_name(Type)]),
     "Pass an Int, SInt, Float, or Number value to range."};
format({range_arity, Expected, Actual}) ->
    {range_arity,
     io_lib:format("range expects ~p argument, but received ~p.", [Expected, Actual]),
     "Write range(limit), for example range(10)."};
format({invalid_numeric_conversion, Source, Target}) ->
    {invalid_numeric_conversion,
     io_lib:format("Cannot convert ~s to ~s.", [type_name(Source), type_name(Target)]),
     "Numeric constructors accept only Int, SInt, Float, or Number values."};
format({numeric_conversion_arity, Target, Expected, Actual}) ->
    {numeric_conversion_arity,
     io_lib:format("~s conversion expects ~p argument, but received ~p.",
                   [type_name(Target), Expected, Actual]),
     "Pass exactly one numeric value to the conversion."};
format(null_not_allowed) ->
    {null_not_allowed,
     "null and nil are not valid variable values.",
     "Use a concrete value or model absence explicitly."};
format({expected_function_declaration, _Tokens}) ->
    {expected_function_declaration,
     "Code was found outside a function.",
     "Move executable code into Main or another function."};
format({expected_return_type, _Tokens}) ->
    {expected_return_type,
     "Every function must declare a return type.",
     "Write function Number Name(...) or another concrete return type."};
format({expected_variable_declaration, _Tokens}) ->
    {expected_variable_declaration,
     "This variable declaration is not valid Terra syntax.",
     "Use scope, optional modifier, type, name, initializer, and a semicolon."};
format({unsupported_statement, _Tokens}) ->
    {unsupported_statement,
     "This statement is not valid Terra syntax yet.",
     "Use a declaration, call, return, condition, switch, or loop statement."};
format(unterminated_function_body) ->
    {unterminated_function_body,
     "A function body is missing its closing brace.",
     "Add } to close the function."};
format(unterminated_statement) ->
    {unterminated_statement,
     "A statement is incomplete.",
     "Finish the statement and add ; where required."};
format({tokenize, {illegal_character, [Character]}}) ->
    {invalid_token,
     io_lib:format("I found the unexpected character '~c'.", [Character]),
     "Remove it or replace it with valid Terra punctuation."};
format({tokenize, unterminated_string}) ->
    {unterminated_string,
     "This string does not have a closing quote.",
     "Add a closing double quote before the end of the line."};
format({tokenize, newline_in_string}) ->
    {newline_in_string,
     "A string continued onto the next line.",
     "Close the string on this line or use an escaped newline."};
format({tokenize, Reason}) ->
    {invalid_token,
     io_lib:format("The source contains an invalid token: ~p.", [Reason]),
     "Check quotes, characters, and punctuation near the invalid text."};
format({backend, {unsupported_statement, Kind}}) ->
    {unsupported_backend_statement,
     io_lib:format("The BEAM backend cannot generate the ~p statement yet.", [Kind]),
     "Run terra check and terra explain, or simplify this statement for now."};
format({backend, {unknown_codegen_variable, Name}}) ->
    {unknown_codegen_variable,
     io_lib:format("The backend could not resolve variable ~s.", [Name]),
     "Make sure the variable is declared before it is used."};
format({erlang_compile, _Errors, _Warnings}) ->
    {beam_compile_failed,
     "Erlang could not compile the generated module.",
     "Use terra emit to inspect the generated Erlang source."};
format({beam_load_failed, Reason}) ->
    {beam_load_failed,
     io_lib:format("The BEAM VM could not load the generated module: ~p.", [Reason]),
     "Rebuild the program and check that the output directory is writable."};
format({runtime_error, Class, Reason, _Stacktrace}) ->
    {runtime_error,
     io_lib:format("The program stopped at runtime (~p): ~p.", [Class, Reason]),
     "Inspect the generated Erlang with terra emit and check the failing value."};
format({write_failed, Reason}) ->
    {write_failed,
     io_lib:format("I could not write the generated Erlang file: ~p.", [Reason]),
     "Choose a writable output path."};
format(Reason) ->
    {compiler_error,
     io_lib:format("The program could not be checked: ~p.", [Reason]),
     "Review the surrounding syntax and run terra explain after it checks."}.

render(Path, Reason) ->
    {Code, Message, Help} = format(Reason),
    Title = lists:flatten(
        string:uppercase(string:replace(atom_to_list(Code), "_", " ", all))),
    case file:read_file(Path) of
        {ok, Source} ->
            Lines = string:split(binary_to_list(Source), "\n", all),
            LocationResult = case locate(Reason) of
                                 none -> locate(Lines, Reason);
                                 SpanLocation -> SpanLocation
                             end,
            case LocationResult of
                none ->
                    [diagnostic_header(Title, Path), "\n",
                     Message, "\n\nHint: ", Help, "\n"];
                {LineNumber, Column, Length} ->
                    Location = io_lib:format("~s:~p:~p", [Path, LineNumber, Column]),
                    [diagnostic_header(Title, Location), "\n",
                     code_frame(Lines, LineNumber, Column, Length), "\n",
                     Message, "\n\nHint: ", Help, "\n"]
            end;
        {error, _} ->
            [diagnostic_header(Title, Path), "\n",
             Message, "\n\nHint: ", Help, "\n"]
    end.

locate({with_span, _Reason, Span}) ->
    span_location(Span);
locate({in_function, _Name, Reason}) ->
    locate(Reason);
locate(_Reason) ->
    none.

span_location(#{start := #{line := Line, column := Column},
                'end' := #{line := Line, column := EndColumn}})
  when Line > 0, Column > 0 ->
    {Line, Column, max(1, EndColumn - Column)};
span_location(#{start := #{line := Line, column := Column}})
  when Line > 0, Column > 0 ->
    {Line, Column, 1};
span_location(_Span) ->
    none.

diagnostic_header(Title, Location) ->
    DashCount = max(3, 34 - length(Title)),
    io_lib:format("-- ~s ~s ~s~n",
                  [Title, lists:duplicate(DashCount, $-), Location]).

locate(Lines, Reason) ->
    {FunctionName, InnerReason} = reason_context(Reason),
    {Start, End} = function_bounds(Lines, FunctionName),
    locate_reason(Lines, Start, End, InnerReason).

reason_context({in_function, Name, Reason}) -> {Name, Reason};
reason_context(Reason) -> {none, Reason}.

function_bounds(Lines, none) -> {1, length(Lines)};
function_bounds(Lines, Name) ->
    case find_line(Lines, 1, length(Lines),
                   fun(Line) -> function_line(Line, Name) end) of
        none -> {1, length(Lines)};
        {Start, _Line} ->
            case find_line(Lines, Start + 1, length(Lines), fun is_function_line/1) of
                none -> {Start, length(Lines)};
                {Next, _} -> {Start, Next - 1}
            end
    end.

function_line(Line, Name) ->
    is_function_line(Line) andalso
    re:run(Line, "\\b" ++ Name ++ "\\s*\\(", [{capture, none}]) == match.

is_function_line(Line) ->
    lists:prefix("function ", string:trim(Line, leading)).

locate_reason(Lines, _Start, _End, {tokenize, {illegal_character, [Character]}}) ->
    locate_substring(Lines, 1, length(Lines), [Character], first);
locate_reason(Lines, Start, End, {expected_boolean_condition, _Type, Expression}) ->
    locate_expression(Lines, Start, End, Expression);
locate_reason(Lines, Start, End, {expected_iterable, _Type, Expression}) ->
    locate_expression(Lines, Start, End, Expression);
locate_reason(Lines, Start, End, non_exhaustive_switch) ->
    locate_substring(Lines, Start, End, "== {", first);
locate_reason(Lines, Start, End, default_case_must_be_last) ->
    locate_substring(Lines, Start, End, "case:", first);
locate_reason(Lines, Start, End, duplicate_default_case) ->
    locate_substring(Lines, Start, End, "case:", last);
locate_reason(Lines, Start, End, {duplicate_case, default}) ->
    locate_substring(Lines, Start, End, "case:", last);
locate_reason(Lines, Start, End, {duplicate_case, _Pattern}) ->
    locate_substring(Lines, Start, End, "case ", last);
locate_reason(Lines, Start, End, {duplicate_variable, Name}) ->
    locate_substring(Lines, Start, End, Name, last);
locate_reason(Lines, Start, End, {invalid_shadowing, Name}) ->
    locate_substring(Lines, Start, End, Name, first);
locate_reason(Lines, Start, End, {return_type_mismatch, _Expected, _Actual}) ->
    case locate_after(Lines, Start, End, "return ") of
        none -> locate_after(Lines, Start, End, " = ");
        Location -> Location
    end;
locate_reason(Lines, Start, End, {argument_type_mismatch, Name, _Expected, _Actual}) ->
    locate_substring(Lines, Start, End, name(Name), first);
locate_reason(Lines, Start, End, {unknown_function, Name}) ->
    locate_substring(Lines, Start, End, name(Name), first);
locate_reason(Lines, Start, End, {unknown_variable, Name}) ->
    locate_substring(Lines, Start, End, Name, first);
locate_reason(Lines, Start, End, {immutable_variable, Name}) ->
    locate_substring(Lines, Start, End, Name, last);
locate_reason(Lines, Start, End, {case_type_mismatch, _Expected, _Actual}) ->
    locate_substring(Lines, Start, End, "case ", first);
locate_reason(Lines, Start, End, {expected_range_number, _Type}) ->
    locate_substring(Lines, Start, End, "range", first);
locate_reason(Lines, Start, End, {range_arity, _Expected, _Actual}) ->
    locate_substring(Lines, Start, End, "range", first);
locate_reason(Lines, Start, End, null_not_allowed) ->
    case locate_substring(Lines, Start, End, "null", first) of
        none -> locate_substring(Lines, Start, End, "nil", first);
        Location -> Location
    end;
locate_reason(Lines, _Start, _End, {invalid_entry_point_signature, _Signature}) ->
    locate_substring(Lines, 1, length(Lines), "Main", first);
locate_reason(_Lines, _Start, _End, missing_entry_point) -> none;
locate_reason(Lines, _Start, _End, {expected_function_declaration, _Tokens}) ->
    first_source_line(Lines);
locate_reason(Lines, Start, _End, unterminated_function_body) ->
    fallback_location(Lines, Start);
locate_reason(Lines, Start, _End, unterminated_statement) ->
    fallback_location(Lines, Start);
locate_reason(Lines, Start, _End, _Reason) ->
    fallback_location(Lines, Start).

is_condition_line(Line) ->
    Trimmed = string:trim(Line, leading),
    lists:any(fun(Keyword) -> lists:prefix(Keyword ++ " ", Trimmed) end,
              ["if", "elseif", "unless", "while", "do_while"]).

locate_expression(Lines, Start, End, Expression) ->
    Text = lists:flatten(expression_text(Expression)),
    case Text == [] of
        true -> locate_condition_fallback(Lines, Start, End);
        false -> locate_expression_text(Lines, Start, End, Text)
    end.

locate_expression_text(Lines, Start, End, Text) ->
    case locate_substring(Lines, Start, End, Text, first) of
        none ->
            locate_condition_fallback(Lines, Start, End);
        Location -> Location
    end.

locate_condition_fallback(Lines, Start, End) ->
    case find_line(Lines, Start, End, fun is_condition_line/1) of
        none -> fallback_location(Lines, Start);
        {Number, Line} -> condition_location(Number, Line)
    end.

expression_text({int, Value}) -> integer_to_list(Value);
expression_text({sint, Value}) -> integer_to_list(Value);
expression_text({float, Value}) -> float_to_list(Value, [short]);
expression_text({string, Value}) -> [$" | binary_to_list(Value)] ++ [$"];
expression_text({bool, true}) -> "true";
expression_text({bool, false}) -> "false";
expression_text({var_ref, Name}) -> Name;
expression_text({binary, Op, Left, Right}) ->
    [expression_text(Left), " ", operator_text(Op), " ", expression_text(Right)];
expression_text(_Expression) -> "".

operator_text(eq_eq) -> "==";
operator_text(not_eq) -> "!=";
operator_text(lt) -> "<";
operator_text(lt_eq) -> "<=";
operator_text(gt) -> ">";
operator_text(gt_eq) -> ">=";
operator_text(plus) -> "+";
operator_text(minus) -> "-";
operator_text(times) -> "*";
operator_text(div_op) -> "/".

condition_location(Number, Line) ->
    Leading = length(Line) - length(string:trim(Line, leading)),
    Trimmed = string:trim(Line, leading),
    Keyword = hd([Word || Word <- ["do_while", "elseif", "unless", "while", "if"],
                          lists:prefix(Word ++ " ", Trimmed)]),
    AfterKeyword = string:slice(Line, Leading + length(Keyword)),
    ExtraSpaces = length(AfterKeyword) - length(string:trim(AfterKeyword, leading)),
    Start = Leading + length(Keyword) + ExtraSpaces,
    Tail = string:slice(Line, Start),
    Condition = case string:split(Tail, "{", leading) of
                    [Value, _] -> string:trim(Value, trailing);
                    [Value] -> string:trim(Value, trailing)
                end,
    {Number, Start + 1, max(1, length(Condition))}.

locate_after(Lines, Start, End, Prefix) ->
    case find_line(Lines, Start, End,
                   fun(Line) -> string:str(Line, Prefix) > 0 end) of
        none -> none;
        {Number, Line} ->
            Position = string:str(Line, Prefix) + length(Prefix),
            Tail = string:slice(Line, Position - 1),
            Value = take_until_delimiter(Tail),
            {Number, Position, max(1, length(Value))}
    end.

take_until_delimiter(Text) ->
    string:trim(take_until_delimiter(Text, [])).

take_until_delimiter([], Acc) -> lists:reverse(Acc);
take_until_delimiter([C | _], Acc) when C == ${; C == $;; C == $, ->
    lists:reverse(Acc);
take_until_delimiter([C | Rest], Acc) ->
    take_until_delimiter(Rest, [C | Acc]).

locate_substring(Lines, Start, End, Needle, Direction) ->
    Matches = [{Number, Line} || {Number, Line} <- numbered_lines(Lines),
                                Number >= Start, Number =< End,
                                string:str(Line, Needle) > 0],
    case choose_match(Matches, Direction) of
        none -> none;
        {Number, Line} -> {Number, string:str(Line, Needle), max(1, length(Needle))}
    end.

choose_match([], _Direction) -> none;
choose_match(Matches, first) -> hd(Matches);
choose_match(Matches, last) -> lists:last(Matches).

first_source_line(Lines) ->
    case find_line(Lines, 1, length(Lines),
                   fun(Line) ->
                       Trimmed = string:trim(Line),
                       Trimmed =/= [] andalso not lists:prefix("--", Trimmed)
                   end) of
        none -> none;
        {Number, Line} ->
            Leading = length(Line) - length(string:trim(Line, leading)),
            {Number, Leading + 1, max(1, length(string:trim(Line)))}
    end.

fallback_location(Lines, LineNumber) when LineNumber >= 1 ->
    case line_at(Lines, LineNumber) of
        none -> none;
        Line ->
            Leading = length(Line) - length(string:trim(Line, leading)),
            {LineNumber, Leading + 1, max(1, length(string:trim(Line)))}
    end.

find_line(Lines, Start, End, Predicate) when Start =< End ->
    case [{Number, Line} || {Number, Line} <- numbered_lines(Lines),
                            Number >= Start, Number =< End, Predicate(Line)] of
        [] -> none;
        [Match | _] -> Match
    end;
find_line(_Lines, _Start, _End, _Predicate) -> none.

numbered_lines(Lines) -> lists:zip(lists:seq(1, length(Lines)), Lines).

line_at(Lines, Number) when Number =< length(Lines) -> lists:nth(Number, Lines);
line_at(_Lines, _Number) -> none.

code_frame(Lines, LineNumber, Column, Length) ->
    Width = length(integer_to_list(LineNumber + 1)),
    Before = frame_line(Lines, LineNumber - 1, Width, " "),
    Current = frame_line(Lines, LineNumber, Width, ">"),
    Pointer = [" ", lists:duplicate(Width, $\s), " | ",
               lists:duplicate(max(0, Column - 1), $\s),
               lists:duplicate(max(1, Length), $^), "\n"],
    After = frame_line(Lines, LineNumber + 1, Width, " "),
    [Before, Current, Pointer, After].

frame_line(Lines, Number, Width, Marker) when Number >= 1, Number =< length(Lines) ->
    io_lib:format("~s ~*B | ~s~n", [Marker, Width, Number, lists:nth(Number, Lines)]);
frame_line(_Lines, _Number, _Width, _Marker) -> [].

name(Value) when is_atom(Value) -> atom_to_list(Value);
name(Value) -> Value.

pattern_name(default) -> "default";
pattern_name({atom, Value}) -> ":" ++ atom_to_list(Value);
pattern_name({int, Value}) -> integer_to_list(Value);
pattern_name({sint, Value}) -> integer_to_list(Value);
pattern_name({float, Value}) -> io_lib:format("~p", [Value]);
pattern_name({string, Value}) -> binary_to_list(Value);
pattern_name({bool, Value}) -> atom_to_list(Value);
pattern_name(Pattern) -> io_lib:format("~p", [Pattern]).

type_list(Types) ->
    ["(", lists:join(", ", [type_name(Type) || Type <- Types]), ")"].

type_name(number) -> "Number";
type_name(int) -> "Int";
type_name(sint) -> "SInt";
type_name(float) -> "Float";
type_name(atom) -> "Atom";
type_name(bool) -> "Bool";
type_name(map) -> "Map";
type_name(list) -> "List";
type_name(tuple) -> "Tuple";
type_name(string) -> "String";
type_name(var) -> "Var";
type_name(Type) -> io_lib:format("~p", [Type]).

statement_name('if') -> "if";
statement_name('for') -> "for";
statement_name(for_each) -> "for_each";
statement_name(do_while) -> "do_while";
statement_name(Kind) -> io_lib:format("~p", [Kind]).
