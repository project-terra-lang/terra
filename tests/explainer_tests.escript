#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Cases = [fun test_inferred_binding_and_return_types/0,
             fun test_control_flow_notes/0,
             fun test_process_and_loop_types/0],
    Results = [Case() || Case <- Cases],
    case lists:member(fail, Results) of
        true ->
            io:format("explainer tests failed~n"),
            halt(1);
        false ->
            io:format("explainer tests passed~n"),
            ok
    end.

test_inferred_binding_and_return_types() ->
    {ok, Program} = program:parse_file("examples/feature_showcase.terra"),
    Text = iolist_to_binary(explainer:format(Program)),
    expect("explainer shows inferred binding and return types",
           contains(Text, <<"declares const Int base from binding showcase_base -> Int">>) andalso
           contains(Text, <<"declares Float parsed_ratio from call to parse_float -> Float">>) andalso
           contains(Text, <<"returns 2 values -> String, Int">>) andalso
           contains(Text, <<"returns 1 value -> *SInt">>)).

test_control_flow_notes() ->
    {ok, Program} = program:parse_file("tests/programs/enums.terra"),
    Text = iolist_to_binary(explainer:format(Program)),
    expect("explainer shows control-flow notes",
           contains(Text, <<"if chain with 1 condition and an else branch; all paths return">>) andalso
           contains(Text, <<"exhaustive switch on Result with 4 case(s); all cases return">>) andalso
           contains(Text, <<"case Result.Ok(value: Int)">>)).

test_process_and_loop_types() ->
    {ok, Processes} = program:parse_file("examples/processes.terra"),
    ProcessText = iolist_to_binary(explainer:format(Processes)),
    {ok, Loops} = program:parse_file("tests/programs/loops.terra"),
    LoopText = iolist_to_binary(explainer:format(Loops)),
    expect("explainer shows process and loop types",
           contains(ProcessText, <<"declares String reply from call to receive -> String">>) andalso
           contains(ProcessText, <<"declares PID worker from call to spawn -> PID">>) andalso
           contains(LoopText, <<"calls Recur normally -> Number">>) andalso
           contains(LoopText, <<"range loop over List; implicit it: Int stays loop-local">>)).

expect(Name, true) ->
    io:format("ok - ~s~n", [Name]),
    pass;
expect(Name, Other) ->
    io:format("not ok - ~s~n  got: ~p~n", [Name, Other]),
    fail.

contains(Text, Needle) ->
    case binary:match(Text, Needle) of
        nomatch -> false;
        _ -> true
    end.
