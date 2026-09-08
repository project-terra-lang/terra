#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Cases = [fun test_formats_messy_source/0,
             fun test_check_formatted_file/0,
             fun test_round_trips_existing_programs/0],
    Results = [Case() || Case <- Cases],
    case lists:member(fail, Results) of
        true ->
            io:format("formatter tests failed~n"),
            halt(1);
        false ->
            io:format("formatter tests passed~n"),
            ok
    end.

test_formats_messy_source() ->
    Path = "/tmp/terra_formatter_messy.terra",
    Source = <<"function   strict   *SInt   Main( *String   Args){local Int value=1+2;return *SInt(value);}">>,
    Expected = <<"function strict *SInt Main(*String Args) {\n",
                 "    local Int value = (1 + 2);\n",
                 "    return *SInt(value);\n",
                 "}\n">>,
    ok = file:write_file(Path, Source),
    case prettyprinter:format_file(Path) of
        {ok, Expected} ->
            io:format("ok - format messy source~n"),
            pass;
        Other ->
            io:format("not ok - format messy source~n  got: ~p~n", [Other]),
            fail
    end.

test_check_formatted_file() ->
    Path = "/tmp/terra_formatter_check.terra",
    Source = <<"function strict *SInt Main(*String Args) {\n",
               "    return *SInt(0);\n",
               "}\n">>,
    Messy = <<"function strict *SInt Main(*String Args){return *SInt(0);}">>,
    ok = file:write_file(Path, Messy),
    First = prettyprinter:check_formatted_file(Path),
    ok = file:write_file(Path, Source),
    Second = prettyprinter:check_formatted_file(Path),
    expect("check formatted file", First == {error, not_formatted} andalso Second == ok).

test_round_trips_existing_programs() ->
    Paths = ["tests/programs/immutable_updates.terra",
             "tests/programs/pointer_depth.terra",
             "tests/programs/enums.terra",
             "tests/programs/std_test_usage.terra",
             "examples/webserver.terra"],
    Results = [round_trip(Path) || Path <- Paths],
    expect("formatted programs parse again", lists:all(fun(Result) -> Result == ok end, Results)).

round_trip(Path) ->
    OutPath = filename:join("/tmp", filename:basename(Path) ++ ".fmt.terra"),
    case prettyprinter:format_file(Path) of
        {ok, Formatted} ->
            ok = file:write_file(OutPath, Formatted),
            case program:parse_file(OutPath) of
                {ok, _Program} -> ok;
                Other -> {parse_failed, Path, Other}
            end;
        Other ->
            {format_failed, Path, Other}
    end.

expect(Name, true) ->
    io:format("ok - ~s~n", [Name]),
    pass;
expect(Name, Other) ->
    io:format("not ok - ~s~n  got: ~p~n", [Name, Other]),
    fail.
