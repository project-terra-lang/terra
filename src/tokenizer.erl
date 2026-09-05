-module(tokenizer).
-export([tokenize/1, tokenize_file/1]).

%% Keyword table
keyword(<<"if">>)     -> {ok, 'if'};
keyword(<<"elseif">>) -> {ok, elseif};
keyword(<<"else">>)   -> {ok, 'else'};
keyword(<<"unless">>) -> {ok, unless};
keyword(<<"case">>)   -> {ok, 'case'};
keyword(<<"for_each">>) -> {ok, for_each};
keyword(<<"for">>)    -> {ok, 'for'};
keyword(<<"in">>)     -> {ok, 'in'};
keyword(<<"range">>)  -> {ok, range};
keyword(<<"while">>)  -> {ok, while};
keyword(<<"do_while">>) -> {ok, do_while};
keyword(<<"stdout">>) -> {ok, stdout};
keyword(<<"function">>) -> {ok, function};
keyword(<<"fn">>)     -> {ok, fn};
keyword(<<"return">>) -> {ok, return};
keyword(<<"let">>)    -> {ok, 'let'};
keyword(<<"global">>) -> {ok, global};
keyword(<<"local">>)  -> {ok, local};
keyword(<<"temp">>)   -> {ok, temp};
keyword(<<"lazy">>)   -> {ok, lazy};
keyword(<<"const">>)  -> {ok, const};
keyword(<<"computed">>) -> {ok, computed};
keyword(<<"atomic">>) -> {ok, atomic};
keyword(<<"thread_local">>) -> {ok, thread_local};
keyword(<<"Number">>) -> {ok, number};
keyword(<<"Int">>)    -> {ok, int};
keyword(<<"SInt">>)   -> {ok, sint};
keyword(<<"Float">>)  -> {ok, float};
keyword(<<"Atom">>)   -> {ok, atom};
keyword(<<"Bool">>)   -> {ok, bool};
keyword(<<"Map">>)    -> {ok, map};
keyword(<<"List">>)   -> {ok, list};
keyword(<<"Tuple">>)  -> {ok, tuple};
keyword(<<"String">>) -> {ok, string};
keyword(<<"State">>)  -> {ok, state};
keyword(<<"Var">>)    -> {ok, var};
keyword(<<"True">>)   -> {ok, true};
keyword(<<"False">>)  -> {ok, false};
keyword(<<"true">>)   -> {ok, true};
keyword(<<"false">>)  -> {ok, false};
keyword(<<"null">>)   -> {ok, null};
keyword(<<"nil">>)    -> {ok, nil};
keyword(<<"_">>)      -> {ok, '_'};
keyword(_)            -> false.

skip_line(<<$\n, Rest/binary>>) -> Rest;
skip_line(<<>>)                 -> <<>>;
skip_line(<<_, Rest/binary>>)   -> skip_line(Rest).

read_string(<<$", Rest/binary>>, Acc) -> {Acc, Rest};

read_string(<<$\\, $n,  Rest/binary>>, Acc) -> read_string(Rest, <<Acc/binary, $\n>>);
read_string(<<$\\, $t,  Rest/binary>>, Acc) -> read_string(Rest, <<Acc/binary, $\t>>);
read_string(<<$\\, $r,  Rest/binary>>, Acc) -> read_string(Rest, <<Acc/binary, $\r>>);
read_string(<<$\\, $",  Rest/binary>>, Acc) -> read_string(Rest, <<Acc/binary, $">>);
read_string(<<$\\, $\\, Rest/binary>>, Acc) -> read_string(Rest, <<Acc/binary, $\\>>);
read_string(<<$\\, C,   _/binary>>, _)      -> error({invalid_escape, [C]});

read_string(<<$\n, _/binary>>, _) -> error(newline_in_string);
read_string(<<>>,  _)             -> error(unterminated_string);

read_string(<<C, Rest/binary>>, Acc) -> read_string(Rest, <<Acc/binary, C>>).

%% Main entry point
tokenize(Binary) when is_binary(Binary) ->
    tokenize(Binary, []).

%% Base case: Empty binary returns the accumulated tokens
tokenize(<<>>, Acc) ->
    lists:reverse(Acc);

%% Skip whitespace
tokenize(<<C, Rest/binary>>, Acc) when C == $\s; C == $\t; C == $\n; C == $\r ->
    tokenize(Rest, Acc);

%% Match multi-character operators (must stay above the single-character block)
tokenize(<<"//", Rest/binary>>, Acc) -> tokenize(skip_line(Rest), Acc);
tokenize(<<"--", Rest/binary>>, Acc) -> tokenize(skip_line(Rest), Acc);
tokenize(<<"==", Rest/binary>>, Acc) -> tokenize(Rest, [{eq_eq, "=="} | Acc]);
tokenize(<<"!=", Rest/binary>>, Acc) -> tokenize(Rest, [{not_eq, "!="} | Acc]);
tokenize(<<"<=", Rest/binary>>, Acc) -> tokenize(Rest, [{lt_eq, "<="} | Acc]);
tokenize(<<">=", Rest/binary>>, Acc) -> tokenize(Rest, [{gt_eq, ">="} | Acc]);
tokenize(<<"=>", Rest/binary>>, Acc) -> tokenize(Rest, [{fat_arrow, "=>"} | Acc]);
tokenize(<<"->", Rest/binary>>, Acc) -> tokenize(Rest, [{arrow, "->"} | Acc]);
tokenize(<<"&&", Rest/binary>>, Acc) -> tokenize(Rest, [{and_and, "&&"} | Acc]);
tokenize(<<"||", Rest/binary>>, Acc) -> tokenize(Rest, [{or_or, "||"} | Acc]);
tokenize(<<"::", Rest/binary>>, Acc) -> tokenize(Rest, [{colon_colon, "::"} | Acc]);

%% Match Single-character operators
tokenize(<<$+, Rest/binary>>, Acc) -> tokenize(Rest, [{plus, "+"} | Acc]);
tokenize(<<$-, Rest/binary>>, Acc) -> tokenize(Rest, [{minus, "-"} | Acc]);
tokenize(<<$*, Rest/binary>>, Acc) -> tokenize(Rest, [{times, "*"} | Acc]);
tokenize(<<$/, Rest/binary>>, Acc) -> tokenize(Rest, [{div_op, "/"} | Acc]);
tokenize(<<$(, Rest/binary>>, Acc) -> tokenize(Rest, [{lparen, "("} | Acc]);
tokenize(<<$), Rest/binary>>, Acc) -> tokenize(Rest, [{rparen, ")"} | Acc]);
tokenize(<<$=, Rest/binary>>, Acc) -> tokenize(Rest, [{equals, "="} | Acc]);
tokenize(<<$;, Rest/binary>>, Acc) -> tokenize(Rest, [{endofline, ";"} | Acc]);
tokenize(<<$:, Rest/binary>>, Acc) -> tokenize(Rest, [{atomprefix, ":"} | Acc]);
tokenize(<<$#, Rest/binary>>, Acc) -> tokenize(Rest, [{hash, "#"} | Acc]);
tokenize(<<$<, Rest/binary>>, Acc) -> tokenize(Rest, [{lt, "<"} | Acc]);
tokenize(<<$>, Rest/binary>>, Acc) -> tokenize(Rest, [{gt, ">"} | Acc]);
tokenize(<<$!, Rest/binary>>, Acc) -> tokenize(Rest, [{bang, "!"} | Acc]);
tokenize(<<$,, Rest/binary>>, Acc) -> tokenize(Rest, [{comma, ","} | Acc]);
tokenize(<<$., Rest/binary>>, Acc) -> tokenize(Rest, [{dot, "."} | Acc]);
tokenize(<<${, Rest/binary>>, Acc) -> tokenize(Rest, [{lbrace, "{"} | Acc]);
tokenize(<<$}, Rest/binary>>, Acc) -> tokenize(Rest, [{rbrace, "}"} | Acc]);
tokenize(<<$[, Rest/binary>>, Acc) -> tokenize(Rest, [{lbracket, "["} | Acc]);
tokenize(<<$], Rest/binary>>, Acc) -> tokenize(Rest, [{rbracket, "]"} | Acc]);

%% Match Digits (Numbers)
tokenize(<<C, Rest/binary>>, Acc) when C >= $0, C =< $9 ->
    {Token, Remaining} = read_number(Rest, <<C>>),
    tokenize(Remaining, [Token | Acc]);

%% Match Identifiers (Variables/Keywords)
tokenize(<<C, Rest/binary>>, Acc) when (C >= $a andalso C =< $z) orelse
                                       (C >= $A andalso C =< $Z) orelse C == $_ ->
    {Word, Remaining} = read_identifier(Rest, <<C>>),
    Token = case keyword(Word) of
                {ok, Kw} -> {keyword, Kw};
                false    -> {id, binary_to_list(Word)}
            end,
    tokenize(Remaining, [Token | Acc]);

%% Match String literals
tokenize(<<$", Rest/binary>>, Acc) ->
    {Str, Remaining} = read_string(Rest, <<>>),
    tokenize(Remaining, [{string, Str} | Acc]);

%% Character literals use Erlang's integer character representation.
tokenize(<<$', C, $', Rest/binary>>, Acc) ->
    tokenize(Rest, [{char, C} | Acc]);

%% Handle syntax errors
tokenize(<<Invalid, _/binary>>, _) ->
    error({illegal_character, [Invalid]}).



%% Helper: Extract consecutive digits
read_number(Bin, Acc) ->
    {IntPart, Rest} = read_digits(Bin, Acc),
    case Rest of
        <<$., D, _/binary>> when D >= $0, D =< $9 ->
            <<$., FracBin/binary>> = Rest,
            {Full, Rest2} = read_digits(FracBin, <<IntPart/binary, $.>>),
            {{float, binary_to_float(Full)}, Rest2};
        _ ->
            {{int, binary_to_integer(IntPart)}, Rest}
    end.

read_digits(<<C, Rest/binary>>, Acc) when C >= $0, C =< $9 ->
    read_digits(Rest, <<Acc/binary, C>>);

read_digits(Rest, Acc) ->
    {Acc, Rest}.


%% Helper: Extract consecutive alphanumeric characters
read_identifier(<<C, Rest/binary>>, Acc) when (C >= $a andalso C =< $z) orelse
                                              (C >= $A andalso C =< $Z) orelse
                                              (C >= $0 andalso C =< $9) orelse
                                              C == $_ ->
    read_identifier(Rest, <<Acc/binary, C>>);

read_identifier(Rest, Acc) ->
    {Acc, Rest}.

tokenize_file(Path) ->
    case first:check_file_extension(Path) of
        not_match ->
            {error, bad_extension};
        match ->
            case file:read_file(Path) of
                {ok, Binary} ->
                    try {ok, tokenize(Binary)}
                    catch
                        error:Reason -> {error, {tokenize, Reason}}
                    end;
                {error, Reason} -> {error, {read_failed, Reason}}
            end
    end.
