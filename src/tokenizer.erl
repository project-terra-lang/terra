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
keyword(<<"import">>) -> {ok, import};
keyword(<<"export">>) -> {ok, export};
keyword(<<"struct">>) -> {ok, struct};
keyword(<<"enum">>)   -> {ok, enum};
keyword(<<"variant">>) -> {ok, variant};
keyword(<<"bind">>)    -> {ok, bind};
keyword(<<"return">>) -> {ok, return};
keyword(<<"try">>)    -> {ok, 'try'};
keyword(<<"let">>)    -> {ok, 'let'};
keyword(<<"global">>) -> {ok, global};
keyword(<<"local">>)  -> {ok, local};
keyword(<<"temp">>)   -> {ok, temp};
keyword(<<"region">>) -> {ok, region};
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
keyword(<<"RestrictedMap">>) -> {ok, restricted_map};
keyword(<<"List">>)   -> {ok, list};
keyword(<<"Tuple">>)  -> {ok, tuple};
keyword(<<"String">>) -> {ok, string};
keyword(<<"State">>)  -> {ok, state};
keyword(<<"Var">>)    -> {ok, var};
keyword(<<"Void">>)   -> {ok, void};
keyword(<<"void">>)   -> {ok, void};
keyword(<<"True">>)   -> {ok, true};
keyword(<<"False">>)  -> {ok, false};
keyword(<<"true">>)   -> {ok, true};
keyword(<<"false">>)  -> {ok, false};
keyword(<<"null">>)   -> {ok, null};
keyword(<<"nil">>)    -> {ok, nil};
keyword(<<"_">>)      -> {ok, '_'};
keyword(_)            -> false.

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
    tokenize(Binary, [], 1, 1, 0).

%% Base case: Empty binary returns the accumulated tokens
tokenize(<<>>, Acc, _Line, _Column, _Offset) ->
    lists:reverse(Acc);

%% Skip whitespace
tokenize(<<C, Rest/binary>>, Acc, Line, Column, Offset)
  when C == $\s; C == $\t; C == $\n; C == $\r ->
    {NextLine, NextColumn, NextOffset} = advance(<<C>>, Line, Column, Offset),
    tokenize(Rest, Acc, NextLine, NextColumn, NextOffset);

%% Match multi-character operators (must stay above the single-character block)
tokenize(<<"//", Rest/binary>>, Acc, Line, Column, Offset) ->
    {L1, C1, O1} = advance(<<"//">>, Line, Column, Offset),
    {Remaining, L2, C2, O2} = skip_line(Rest, L1, C1, O1),
    tokenize(Remaining, Acc, L2, C2, O2);
tokenize(<<"--", Rest/binary>>, Acc, Line, Column, Offset) ->
    {L1, C1, O1} = advance(<<"--">>, Line, Column, Offset),
    {Remaining, L2, C2, O2} = skip_line(Rest, L1, C1, O1),
    tokenize(Remaining, Acc, L2, C2, O2);
tokenize(<<"==", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(eq_eq, "==", <<"==">>, Rest, Acc, Line, Column, Offset);
tokenize(<<"!=", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(not_eq, "!=", <<"!=">>, Rest, Acc, Line, Column, Offset);
tokenize(<<"<=", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(lt_eq, "<=", <<"<=">>, Rest, Acc, Line, Column, Offset);
tokenize(<<">=", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(gt_eq, ">=", <<">=">>, Rest, Acc, Line, Column, Offset);
tokenize(<<"=>", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(fat_arrow, "=>", <<"=>">>, Rest, Acc, Line, Column, Offset);
tokenize(<<"->", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(arrow, "->", <<"->">>, Rest, Acc, Line, Column, Offset);
tokenize(<<"&&", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(and_and, "&&", <<"&&">>, Rest, Acc, Line, Column, Offset);
tokenize(<<"||", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(or_or, "||", <<"||">>, Rest, Acc, Line, Column, Offset);
tokenize(<<"|>", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(pipe_op, "|>", <<"|>">>, Rest, Acc, Line, Column, Offset);
tokenize(<<"::", Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(colon_colon, "::", <<"::">>, Rest, Acc, Line, Column, Offset);

%% Match Single-character operators
tokenize(<<$+, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(plus, "+", <<$+>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$-, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(minus, "-", <<$->>, Rest, Acc, Line, Column, Offset);
tokenize(<<$*, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(times, "*", <<$*>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$/, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(div_op, "/", <<$/>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$(, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(lparen, "(", <<$(>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$), Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(rparen, ")", <<$)>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$=, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(equals, "=", <<$=>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$;, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(endofline, ";", <<$;>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$:, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(atomprefix, ":", <<$:>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$#, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(hash, "#", <<$#>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$<, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(lt, "<", <<$<>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$>, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(gt, ">", <<$>>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$!, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(bang, "!", <<$!>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$,, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(comma, ",", <<$,>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$., Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(dot, ".", <<$.>>, Rest, Acc, Line, Column, Offset);
tokenize(<<${, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(lbrace, "{", <<${>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$}, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(rbrace, "}", <<$}>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$[, Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(lbracket, "[", <<$[>>, Rest, Acc, Line, Column, Offset);
tokenize(<<$], Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(rbracket, "]", <<$]>>, Rest, Acc, Line, Column, Offset);

%% Match Digits (Numbers)
tokenize(<<C, Rest/binary>> = Input, Acc, Line, Column, Offset) when C >= $0, C =< $9 ->
    {Token, Remaining} = read_number(Rest, <<C>>),
    emit_token(Token, Input, Remaining, Acc, Line, Column, Offset);

%% Match Identifiers (Variables/Keywords)
tokenize(<<C, Rest/binary>> = Input, Acc, Line, Column, Offset)
  when (C >= $a andalso C =< $z) orelse
       (C >= $A andalso C =< $Z) orelse C == $_ ->
    {Word, Remaining} = read_identifier(Rest, <<C>>),
    Token = case keyword(Word) of
                {ok, Kw} -> {keyword, Kw};
                false    -> {id, binary_to_list(Word)}
            end,
    emit_token(Token, Input, Remaining, Acc, Line, Column, Offset);

%% Match String literals
tokenize(<<$", Rest/binary>> = Input, Acc, Line, Column, Offset) ->
    {Str, Remaining} = read_string(Rest, <<>>),
    emit_token({string, Str}, Input, Remaining, Acc, Line, Column, Offset);

%% Character literals use Erlang's integer character representation.
tokenize(<<$', C, $', Rest/binary>>, Acc, Line, Column, Offset) ->
    emit(char, C, <<$', C, $'>>, Rest, Acc, Line, Column, Offset);

%% Handle syntax errors
tokenize(<<Invalid, _/binary>>, _Acc, _Line, _Column, _Offset) ->
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

emit_token({Kind, Value}, Input, Remaining, Acc, Line, Column, Offset) ->
    Size = byte_size(Input) - byte_size(Remaining),
    Lexeme = binary:part(Input, 0, Size),
    emit(Kind, Value, Lexeme, Remaining, Acc, Line, Column, Offset).

emit(Kind, Value, Lexeme, Rest, Acc, Line, Column, Offset) ->
    Span = span(Line, Column, Offset, Lexeme),
    {NextLine, NextColumn, NextOffset} = advance(Lexeme, Line, Column, Offset),
    tokenize(Rest, [{Kind, Value, Span} | Acc], NextLine, NextColumn, NextOffset).

span(Line, Column, Offset, Lexeme) ->
    {EndLine, EndColumn, EndOffset} = advance(Lexeme, Line, Column, Offset),
    #{start => #{line => Line, column => Column, offset => Offset},
      'end' => #{line => EndLine, column => EndColumn, offset => EndOffset}}.

advance(Binary, Line, Column, Offset) ->
    advance_chars(Binary, Line, Column, Offset).

advance_chars(<<>>, Line, Column, Offset) ->
    {Line, Column, Offset};
advance_chars(<<$\n, Rest/binary>>, Line, _Column, Offset) ->
    advance_chars(Rest, Line + 1, 1, Offset + 1);
advance_chars(<<_C, Rest/binary>>, Line, Column, Offset) ->
    advance_chars(Rest, Line, Column + 1, Offset + 1).

skip_line(<<$\n, Rest/binary>>, Line, Column, Offset) ->
    {NextLine, NextColumn, NextOffset} = advance(<<$\n>>, Line, Column, Offset),
    {Rest, NextLine, NextColumn, NextOffset};
skip_line(<<>>, Line, Column, Offset) ->
    {<<>>, Line, Column, Offset};
skip_line(<<C, Rest/binary>>, Line, Column, Offset) ->
    {NextLine, NextColumn, NextOffset} = advance(<<C>>, Line, Column, Offset),
    skip_line(Rest, NextLine, NextColumn, NextOffset).

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
