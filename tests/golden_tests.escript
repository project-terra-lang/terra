#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Cases = [{"generated Erlang source golden", fun source_golden/0},
             {"missing return diagnostic golden", fun missing_return_golden/0},
             {"top-level local diagnostic golden", fun top_level_local_golden/0},
             {"invalid token diagnostic golden", fun invalid_token_golden/0}],
    Results = [run_case(Case) || Case <- Cases],
    case lists:member(fail, Results) of
        true ->
            io:format("golden tests failed~n"),
            halt(1);
        false ->
            io:format("golden tests passed~n"),
            ok
    end.

run_case({Name, Expect}) ->
    case Expect() of
        true ->
            io:format("ok - ~s~n", [Name]),
            pass;
        false ->
            io:format("not ok - ~s~n~n", [Name]),
            fail
    end.

source_golden() ->
    Path = "tests/programs/module_declarations.terra",
    GoldenPath = "tests/golden/source/module_declarations.erl",
    case {transpiler:transpile_file(Path), file:read_file(GoldenPath)} of
        {{ok, terra_module_declarations, Source}, {ok, Expected}} ->
            compare(GoldenPath, Expected, iolist_to_binary(Source));
        Other ->
            io:format("golden setup failed: ~p~n", [Other]),
            false
    end.

missing_return_golden() ->
    diagnostic_golden("tests/programs/missing_return.terra",
                      "tests/golden/diagnostics/missing_return.txt").

top_level_local_golden() ->
    diagnostic_golden("tests/programs/top_level_local.terra",
                      "tests/golden/diagnostics/top_level_local.txt").

invalid_token_golden() ->
    diagnostic_golden("tests/programs/invalid_token.terra",
                      "tests/golden/diagnostics/invalid_token.txt").

diagnostic_golden(Path, GoldenPath) ->
    case {program:parse_file(Path), file:read_file(GoldenPath)} of
        {{error, Reason}, {ok, Expected}} ->
            compare(GoldenPath, Expected, iolist_to_binary(diagnostics:render(Path, Reason)));
        {Other, _Expected} ->
            io:format("expected diagnostic for ~s, got ~p~n", [Path, Other]),
            false
    end.

compare(_GoldenPath, Expected, Actual) when Expected == Actual ->
    true;
compare(GoldenPath, Expected, Actual) ->
    io:format("golden mismatch: ~s~n", [GoldenPath]),
    print_first_difference(binary:split(Expected, <<"\n">>, [global]),
                           binary:split(Actual, <<"\n">>, [global]), 1),
    false.

print_first_difference([], [], _Line) ->
    io:format("outputs differ but no line difference was found~n");
print_first_difference([Expected | RestExpected], [Actual | RestActual], Line) ->
    case Expected == Actual of
        true -> print_first_difference(RestExpected, RestActual, Line + 1);
        false ->
            io:format("line ~p expected: ~ts~n", [Line, Expected]),
            io:format("line ~p actual:   ~ts~n", [Line, Actual])
    end;
print_first_difference([], [Actual | _], Line) ->
    io:format("line ~p expected end of file~n", [Line]),
    io:format("line ~p actual:   ~ts~n", [Line, Actual]);
print_first_difference([Expected | _], [], Line) ->
    io:format("line ~p expected: ~ts~n", [Line, Expected]),
    io:format("line ~p actual end of file~n", [Line]).
