#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Path = "tests/programs/backend_run.terra",
    OutDir = "/tmp/terra_backend_tests",
    Results = [test_codegen_pass(Path), test_transpile(Path), test_compile(Path, OutDir), test_run(Path, OutDir),
               test_showcase_compile(OutDir)],
    case lists:member(fail, Results) of
        true ->
            io:format("backend tests failed~n"),
            halt(1);
        false ->
            io:format("backend tests passed~n"),
            ok
    end.

test_codegen_pass(Path) ->
    case program:parse_file(Path) of
        {ok, Program} ->
            case transpiler:codegen_pass(#{module => terra_backend_run, program => Program}) of
                {ok, #{source := Source, passes := Passes}} ->
                    Binary = iolist_to_binary(Source),
                    expect("codegen pass",
                           contains(Binary, <<"-module(terra_backend_run).">>) andalso
                           lists:last(Passes) == codegen);
                Other ->
                    io:format("not ok - codegen pass~n  got: ~p~n", [Other]),
                    fail
            end;
        Other ->
            io:format("not ok - codegen pass parse~n  got: ~p~n", [Other]),
            fail
    end.

test_transpile(Path) ->
    case transpiler:transpile_file(Path) of
        {ok, terra_backend_run, Source} ->
            Binary = iolist_to_binary(Source),
            expect("transpile", contains(Binary, <<"-module(terra_backend_run).">>) andalso
                                contains(Binary, <<"terra_fn_main">>) andalso
                                contains(Binary, <<"terra_for_range">>));
        Other ->
            io:format("not ok - transpile~n  got: ~p~n", [Other]),
            fail
    end.

test_compile(Path, OutDir) ->
    case transpiler:compile_file(Path, OutDir) of
        {ok, terra_backend_run, BeamPath, ErlangPath} ->
            expect("compile", filelib:is_file(BeamPath) andalso filelib:is_file(ErlangPath));
        Other ->
            io:format("not ok - compile~n  got: ~p~n", [Other]),
            fail
    end.

test_run(Path, OutDir) ->
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_backend_run, 7, _BeamPath, _ErlangPath} ->
            expect("run on BEAM", true);
        Other ->
            io:format("not ok - run on BEAM~n  got: ~p~n", [Other]),
            fail
    end.

test_showcase_compile(OutDir) ->
    Path = "examples/feature_showcase.terra",
    case transpiler:compile_file(Path, OutDir) of
        {ok, terra_feature_showcase, BeamPath, _ErlangPath} ->
            expect("compile feature showcase", filelib:is_file(BeamPath));
        Other ->
            io:format("not ok - compile feature showcase~n  got: ~p~n", [Other]),
            fail
    end.

expect(Name, true) ->
    io:format("ok - ~s~n", [Name]),
    pass;
expect(Name, false) ->
    io:format("not ok - ~s~n", [Name]),
    fail.

contains(Binary, Needle) ->
    binary:match(Binary, Needle) =/= nomatch.
