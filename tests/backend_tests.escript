#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Path = "tests/programs/backend_run.terra",
    OutDir = "/tmp/terra_backend_tests",
    Results = [test_codegen_pass(Path), test_transpile(Path), test_compile(Path, OutDir), test_run(Path, OutDir),
               test_short_circuit(OutDir), test_numeric_rules(OutDir),
               test_tail_recursion(OutDir),
               test_once_semantics(OutDir), test_once_failure(OutDir),
               test_once_reentrancy(OutDir),
               test_storage_semantics(OutDir), test_computed_deferred(OutDir),
               test_source_map(OutDir),
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

test_short_circuit(OutDir) ->
    Path = "tests/programs/backend_short_circuit.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_backend_short_circuit, 7, _BeamPath, _ErlangPath} ->
            expect("short-circuit boolean operators", true);
        Other ->
            io:format("not ok - short-circuit boolean operators~n  got: ~p~n", [Other]),
            fail
    end.

test_numeric_rules(OutDir) ->
    Path = "tests/programs/backend_numeric_rules.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_backend_numeric_rules, 5, _BeamPath, _ErlangPath} ->
            expect("numeric conversions and mixed arithmetic", true);
        Other ->
            io:format("not ok - numeric conversions and mixed arithmetic~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_tail_recursion(OutDir) ->
    Path = "tests/programs/backend_tail_recursion.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_backend_tail_recursion, Source},
         {ok, terra_backend_tail_recursion, 200000, BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("real tail-recursive dispatch",
                   contains(Binary, <<"terra_fn_count_tail_step">>) andalso
                   contains(Binary,
                            <<"{terra_tail_call, \"Count\", [TerraTailArg1, TerraTailArg2]} -> terra_fn_count(TerraTailArg1, TerraTailArg2)">>) andalso
                   has_beam_tail_call(BeamPath, terra_fn_count, 2));
        Other ->
            io:format("not ok - real tail-recursive dispatch~n  got: ~p~n", [Other]),
            fail
    end.

has_beam_tail_call(BeamPath, Function, Arity) ->
    case beam_disasm:file(BeamPath) of
        {beam_file, _Module, _Exports, _Attributes, _CompileInfo, Functions} ->
            lists:any(
              fun({function, Candidate, CandidateArity, _Label, Instructions})
                    when Candidate =:= Function, CandidateArity =:= Arity ->
                      lists:any(fun(Instruction) ->
                          is_tail_instruction(Instruction, Function, Arity)
                      end, Instructions);
                 (_) -> false
              end, Functions);
        _ -> false
    end.

is_tail_instruction({call_last, Arity, {_Module, Function, Arity}, _Deallocate},
                    Function, Arity) -> true;
is_tail_instruction({call_only, Arity, {_Module, Function, Arity}}, Function, Arity) -> true;
is_tail_instruction(_Instruction, _Function, _Arity) -> false.

test_once_semantics(OutDir) ->
    Path = "tests/programs/backend_once_semantics.terra",
    Module = terra_backend_once_semantics,
    StoreKey = {Module, terra_once, "Touch"},
    NormalKey = {Module, terra_once, "Normal"},
    erlang:erase(StoreKey),
    erlang:erase(NormalKey),
    case transpiler:run_file(Path, "", OutDir) of
        {ok, Module, 7, _BeamPath, _ErlangPath} ->
            FirstCache = erlang:get(StoreKey),
            SecondResult = apply(Module, main, [<<>>]),
            SecondCache = erlang:get(StoreKey),
            Parent = self(),
            spawn(fun() ->
                Result = apply(Module, main, [<<>>]),
                Parent ! {once_child, Result, erlang:get(StoreKey)}
            end),
            ChildResult = receive
                {once_child, Result, Cache} -> {Result, Cache}
            after 5000 -> timeout
            end,
            NormalCache = erlang:get(NormalKey),
            erlang:erase(StoreKey),
            expect("once-only process-local success cache",
                   FirstCache == {done, 9} andalso
                   SecondResult == 7 andalso SecondCache == {done, 9} andalso
                   ChildResult == {7, {done, 9}} andalso
                   NormalCache == undefined);
        Other ->
            io:format("not ok - once-only process-local success cache~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_once_failure(OutDir) ->
    Path = "tests/programs/backend_once_failure.terra",
    StoreKey = {terra_backend_once_failure, terra_once, "Fail"},
    erlang:erase(StoreKey),
    Result = transpiler:run_file(Path, "", OutDir),
    Cache = erlang:get(StoreKey),
    expect("failed once-only calls are retryable",
           is_runtime_reason(Result, badarith) andalso Cache == undefined).

test_once_reentrancy(OutDir) ->
    Path = "tests/programs/backend_once_reentrant.terra",
    StoreKey = {terra_backend_once_reentrant, terra_once, "Reenter"},
    erlang:erase(StoreKey),
    Result = transpiler:run_file(Path, "", OutDir),
    Cache = erlang:get(StoreKey),
    expect("reentrant once-only calls fail explicitly",
           is_runtime_reason(Result, {terra_once_reentrant, "Reenter"}) andalso
           Cache == undefined).

is_runtime_reason({error, {runtime_error, error, Reason, _Stacktrace}}, Reason) -> true;
is_runtime_reason(_Result, _Reason) -> false.

test_storage_semantics(OutDir) ->
    Path = "tests/programs/backend_storage_semantics.terra",
    Module = terra_backend_storage_semantics,
    GlobalKey = {Module, terra_global, "shared"},
    AtomicKey = {Module, terra_global, {atomic, "global_counter"}},
    MultiKey = {Module, terra_global, {multi, ["first", "second"]}},
    ThreadKey = {Module, terra_thread_local, {"Main", "session", 3}},
    persistent_term:erase(GlobalKey),
    persistent_term:erase(AtomicKey),
    persistent_term:erase(MultiKey),
    erlang:erase(ThreadKey),
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, Module, Source}, {ok, Module, 102, _BeamPath, _ErlangPath}} ->
            ParentThread = erlang:get(ThreadKey),
            {done, GlobalAtomic} = persistent_term:get(AtomicKey),
            Parent = self(),
            spawn(fun() ->
                Result = apply(Module, main, [<<>>]),
                Parent ! {storage_child, Result, erlang:get(ThreadKey),
                          persistent_term:get(AtomicKey)}
            end),
            Child = receive
                {storage_child, ChildValue, ChildThread, ChildAtomic} ->
                    {ChildValue, ChildThread, ChildAtomic}
            after 5000 -> timeout
            end,
            Binary = iolist_to_binary(Source),
            Valid = persistent_term:get(GlobalKey) == {done, 11} andalso
                    atomics:get(GlobalAtomic, 1) == 4 andalso
                    persistent_term:get(MultiKey) == {done, {5, 6}} andalso
                    ParentThread == {done, 22} andalso
                    Child == {102, {done, 22}, {done, GlobalAtomic}} andalso
                    contains(Binary, <<"Terra_total_8 = fun() ->">>) andalso
                    contains(Binary, <<"Terra_total_8() + Terra_total_8()">>),
            persistent_term:erase(GlobalKey),
            persistent_term:erase(AtomicKey),
            persistent_term:erase(MultiKey),
            erlang:erase(ThreadKey),
            expect("global, atomic, thread-local, and computed storage", Valid);
        Other ->
            persistent_term:erase(GlobalKey),
            persistent_term:erase(AtomicKey),
            persistent_term:erase(MultiKey),
            erlang:erase(ThreadKey),
            io:format("not ok - global, atomic, thread-local, and computed storage~n"
                      "  got: ~p~n", [Other]),
            fail
    end.

test_computed_deferred(OutDir) ->
    Path = "tests/programs/backend_computed_deferred.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_backend_computed_deferred, 7, _BeamPath, _ErlangPath} ->
            expect("computed initializer is deferred", true);
        Other ->
            io:format("not ok - computed initializer is deferred~n  got: ~p~n", [Other]),
            fail
    end.

test_source_map(OutDir) ->
    Path = "tests/programs/backend_source_map.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_backend_source_map, Source},
         {error, {runtime_error, error, badarith, Stacktrace}}} ->
            Binary = iolist_to_binary(Source),
            expect("runtime stack preserves Terra source map",
                   contains(Binary, <<"-file(\"tests/programs/backend_source_map.terra\"">>)
                   andalso has_terra_frame(Stacktrace, Path));
        Other ->
            io:format("not ok - runtime stack preserves Terra source map~n  got: ~p~n",
                      [Other]),
            fail
    end.

has_terra_frame(Stacktrace, Path) ->
    lists:any(fun({_Module, _Function, _Arity, Info}) ->
                      proplists:get_value(file, Info) == Path andalso
                      proplists:get_value(line, Info, 0) > 0;
                 (_) -> false
              end, Stacktrace).

expect(Name, true) ->
    io:format("ok - ~s~n", [Name]),
    pass;
expect(Name, false) ->
    io:format("not ok - ~s~n", [Name]),
    fail.

contains(Binary, Needle) ->
    binary:match(Binary, Needle) =/= nomatch.
