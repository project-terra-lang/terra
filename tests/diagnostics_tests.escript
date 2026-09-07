#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Error = iolist_to_binary(
        diagnostics:render("tests/programs/missing_return.terra",
                           {in_function, "Main", {missing_return, [number]}})),
    Warning = iolist_to_binary(
        diagnostics:render_warning(
            "tests/programs/warnings.terra",
            #{code => unused_variable, function => "Main", name => "unused"})),
    Results = [expect("diagnostic title",
                      contains(Error, <<"MISSING RETURN [missing_return]">>)),
               expect("warning title",
                      contains(Warning,
                               <<"WARNING UNUSED VARIABLE [unused_variable]">>))],
    case lists:member(fail, Results) of
        true -> halt(1);
        false -> io:format("diagnostics tests passed~n")
    end.

expect(Name, true) ->
    io:format("ok - ~s~n", [Name]),
    pass;
expect(Name, false) ->
    io:format("not ok - ~s~n", [Name]),
    fail.

contains(Binary, Needle) ->
    binary:match(Binary, Needle) =/= nomatch.
