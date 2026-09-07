#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Cases = [{"token spans", fun expect_token_spans/0},
             {"pipe operator token", fun expect_pipe_token/0},
             {"program ast span", fun expect_program_span/0}],
    Results = [run_case(Case) || Case <- Cases],
    case lists:member(fail, Results) of
        true ->
            io:format("tokenizer tests failed~n"),
            halt(1);
        false ->
            io:format("tokenizer tests passed~n"),
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

expect_token_spans() ->
    Tokens = tokenizer:tokenize(<<"local Int x = 10;\nstdout(x);">>),
    [{keyword, local, FirstSpan} | _] = Tokens,
    {id, "x", XSpan} = lists:nth(3, Tokens),
    {keyword, stdout, StdoutSpan} = lists:nth(7, Tokens),
    span_start(FirstSpan) == #{line => 1, column => 1, offset => 0} andalso
    span_start(XSpan) == #{line => 1, column => 11, offset => 10} andalso
    span_start(StdoutSpan) == #{line => 2, column => 1, offset => 18}.

expect_pipe_token() ->
    [{int, 2, _}, {pipe_op, "|>", Span}, {id, "Increment", _},
     {lparen, "(", _}, {rparen, ")", _}] = tokenizer:tokenize(<<"2 |> Increment()">>),
    span_start(Span) == #{line => 1, column => 3, offset => 2}.

expect_program_span() ->
    case program:parse_file("tests/programs/main_ok.terra") of
        {ok, Program} ->
            Functions = maps:get(functions, Program),
            Main = hd(Functions),
            has_real_span(Program) andalso has_real_span(Main);
        Error ->
            Error
    end.

has_real_span(Node) ->
    Span = maps:get(span, Node),
    Start = maps:get(start, Span),
    maps:get(line, Start) >= 1 andalso maps:get(column, Start) >= 1.

span_start(Span) ->
    maps:get(start, Span).
