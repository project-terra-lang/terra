#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Path = "tests/programs/backend_run.terra",
    OutDir = "/tmp/terra_backend_tests",
    Results = [test_codegen_pass(Path), test_transpile(Path),
               test_deterministic_output(Path, OutDir),
               test_compile(Path, OutDir), test_run(Path, OutDir),
               test_short_circuit(OutDir), test_numeric_rules(OutDir),
               test_try_success(OutDir), test_try_failure(OutDir),
               test_pipe_success(OutDir), test_pipe_failure(OutDir),
               test_tail_recursion(OutDir),
               test_once_semantics(OutDir), test_once_failure(OutDir),
               test_once_reentrancy(OutDir),
               test_storage_semantics(OutDir), test_computed_deferred(OutDir),
               test_conversions(OutDir), test_conversion_bad_string(OutDir),
               test_console_helpers(OutDir), test_format_failures(OutDir),
               test_restricted_map(OutDir),
               test_immutable_updates(OutDir), test_restricted_map_update_overflow(OutDir),
               test_state_type(OutDir),
               test_records(OutDir),
               test_enums(OutDir),
               test_enum_pattern_ignore(OutDir),
               test_pointers(OutDir), test_pointer_depth(OutDir),
               test_pointer_auto_region(OutDir),
               test_pointer_region_overflow(OutDir),
               test_switch_function_case(OutDir),
               test_module_declarations(OutDir), test_module_const_priority(OutDir),
               test_imports_exports(OutDir),
               test_std_collection(OutDir),
               test_std_helpers(OutDir),
               test_std_test(OutDir),
               test_erlang_ffi(OutDir),
               test_webserver_ffi(OutDir),
               test_otp_library_first(OutDir),
               test_erlang_term_mapping(OutDir),
               test_erlang_return_validation(OutDir),
               test_beam_value_types(OutDir),
               test_process_primitives(OutDir),
               test_invalid_process_message(OutDir),
               test_source_map(OutDir),
               test_showcase_run(OutDir), test_counter_example(OutDir)],
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

test_deterministic_output(Path, OutDir) ->
    FirstSource = transpiler:transpile_file(Path),
    SecondSource = transpiler:transpile_file(Path),
    FirstCompile = transpiler:compile_file(Path, OutDir),
    FirstBeam = beam_contents(FirstCompile),
    SecondCompile = transpiler:compile_file(Path, OutDir),
    SecondBeam = beam_contents(SecondCompile),
    case {FirstSource, SecondSource, FirstBeam, SecondBeam} of
        {{ok, Module, Source1}, {ok, Module, Source2},
         {ok, Beam1}, {ok, Beam2}} ->
            expect("deterministic compiler output",
                   iolist_to_binary(Source1) == iolist_to_binary(Source2) andalso
                   Beam1 == Beam2);
        Other ->
            io:format("not ok - deterministic compiler output~n  got: ~p~n", [Other]),
            fail
    end.

beam_contents({ok, _Module, BeamPath, _ErlangPath}) -> file:read_file(BeamPath);
beam_contents(Error) -> Error.

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

test_showcase_run(OutDir) ->
    Path = "examples/feature_showcase.terra",
    case transpiler:run_file(Path, "milestone two", OutDir) of
        {ok, terra_feature_showcase, 14, _BeamPath, _ErlangPath} ->
            expect("run feature showcase on BEAM", true);
        Other ->
            io:format("not ok - run feature showcase on BEAM~n  got: ~p~n", [Other]),
            fail
    end.

test_counter_example(OutDir) ->
    Path = "examples/counter.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_counter, 5, _BeamPath, _ErlangPath} ->
            expect("run counter example on BEAM", true);
        Other ->
            io:format("not ok - run counter example on BEAM~n  got: ~p~n", [Other]),
            fail
    end.

test_otp_library_first(OutDir) ->
    Path = "examples/otp_library_first.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_otp_library_first, Source},
         {ok, terra_otp_library_first, 0, _BeamPath, _ErlangPath}} ->
            expect("OTP integration stays library-first",
                   contains(iolist_to_binary(Source),
                            <<"filename:basename(Terra_path_">>));
        Other ->
            io:format("not ok - OTP integration stays library-first~n  got: ~p~n",
                      [Other]),
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

test_try_success(OutDir) ->
    Path = "tests/programs/try_success.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_try_success, Source},
         {ok, terra_try_success, 5, _BeamPath, _ErlangPath}} ->
            expect("try returns successful function values",
                   contains(iolist_to_binary(Source),
                            <<"terra_try(fun() -> terra_fn_add(2, 3) end)">>));
        Other ->
            io:format("not ok - try returns successful function values~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_try_failure(OutDir) ->
    Path = "tests/programs/try_failure.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {error, {runtime_error, error, badarith, Stacktrace}} ->
            expect("try propagates function failures",
                   has_terra_frame(Stacktrace, Path));
        Other ->
            io:format("not ok - try propagates function failures~n  got: ~p~n", [Other]),
            fail
    end.

test_pipe_success(OutDir) ->
    Path = "tests/programs/pipe_success.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_pipe_success, Source},
         {ok, terra_pipe_success, 6, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("pipe injects values and chains left-to-right",
                   contains(Binary, <<"terra_pipe(fun() -> 2 end">>) andalso
                   contains(Binary, <<"terra_fn_add(TerraPipeValue, 3)">>));
        Other ->
            io:format("not ok - pipe injects values and chains left-to-right~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_pipe_failure(OutDir) ->
    Path = "tests/programs/pipe_failure.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {error, {runtime_error, error, badarith, Stacktrace}} ->
            expect("pipe propagates function failures",
                   has_terra_frame(Stacktrace, Path));
        Other ->
            io:format("not ok - pipe propagates function failures~n  got: ~p~n", [Other]),
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

test_conversions(OutDir) ->
    Path = "tests/programs/conversions.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "echo", OutDir)} of
        {{ok, terra_conversions, Source},
         {ok, terra_conversions, 14, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("safe conversion helpers run on BEAM",
                   contains(Binary, <<"terra_parse_int(">>) andalso
                   contains(Binary, <<"terra_to_binary(">>));
        Other ->
            io:format("not ok - safe conversion helpers run on BEAM~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_conversion_bad_string(OutDir) ->
    Path = "tests/programs/conversion_bad_string.terra",
    Result = transpiler:run_file(Path, "not-a-number", OutDir),
    expect("string parse failures are explicit",
           is_runtime_reason(Result, {invalid_conversion, string, int,
                                      <<"not-a-number">>})).

test_console_helpers(OutDir) ->
    Path = "examples/console_helpers.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "terra", OutDir)} of
        {{ok, terra_console_helpers, Source},
         {ok, terra_console_helpers, 0, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("console and formatting helpers run on BEAM",
                   contains(Binary, <<"terra_console_print(standard_io, false">>) andalso
                   contains(Binary, <<"terra_console_print(standard_error, true">>) andalso
                   contains(Binary, <<"terra_format(">>) andalso
                   contains(Binary, <<"invalid_format_template">>) andalso
                   contains(Binary, <<"format_arity">>));
        Other ->
            io:format("not ok - console and formatting helpers run on BEAM~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_format_failures(OutDir) ->
    ArityResult = transpiler:run_file("tests/programs/format_bad_arity.terra",
                                     "", OutDir),
    TemplateResult = transpiler:run_file("tests/programs/format_bad_template.terra",
                                        "", OutDir),
    expect("format failures are explicit",
           is_runtime_reason(ArityResult, {format_arity, 2, 1}) andalso
           is_runtime_reason(TemplateResult,
                             {invalid_format_template, <<"unclosed {">>})).

test_restricted_map(OutDir) ->
    Path = "tests/programs/restricted_map.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_restricted_map, 4, _BeamPath, _ErlangPath} ->
            expect("restricted and ordinary map properties", true);
        Other ->
            io:format("not ok - restricted and ordinary map properties~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_immutable_updates(OutDir) ->
    Path = "tests/programs/immutable_updates.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "Ada", OutDir)} of
        {{ok, terra_immutable_updates, Source},
         {ok, terra_immutable_updates, 7, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("immutable updates run on BEAM",
                   contains(Binary, <<"terra_update(">>) andalso
                   contains(Binary, <<"terra_apply_updates(">>));
        Other ->
            io:format("not ok - immutable updates run on BEAM~n  got: ~p~n", [Other]),
            fail
    end.

test_restricted_map_update_overflow(OutDir) ->
    Path = "tests/programs/restricted_map_update_overflow.terra",
    Result = transpiler:run_file(Path, "", OutDir),
    expect("restricted map updates enforce capacity",
           is_runtime_reason(Result, {invalid_restricted_map, 1,
                                      #{first => 1, second => 2}})).

test_state_type(OutDir) ->
    Path = "tests/programs/state_type.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "Ada", OutDir)} of
        {{ok, terra_state_type, Source},
         {ok, terra_state_type, 3, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("State snapshots are useful map-backed values",
                   contains(Binary, <<"terra_ffi_valid(state, Value) -> is_map(Value)">>) andalso
                   contains(Binary, <<"terra_receive(state)">>) andalso
                   contains(Binary, <<"terra_update(">>));
        Other ->
            io:format("not ok - State snapshots are useful map-backed values~n"
                      "  got: ~p~n", [Other]),
            fail
    end.

test_records(OutDir) ->
    Path = "tests/programs/records.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "records", OutDir)} of
        {{ok, terra_records, Source},
         {ok, terra_records, 7, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("user-defined records run on BEAM",
                   contains(Binary, <<"#{'$terra_struct' => 'Player'">>) andalso
                   contains(Binary, <<"terra_member(">>));
        Other ->
            io:format("not ok - user-defined records run on BEAM~n  got: ~p~n", [Other]),
            fail
    end.

test_enums(OutDir) ->
    Path = "tests/programs/enums.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "enums", OutDir)} of
        {{ok, terra_enums, Source},
         {ok, terra_enums, 7, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("tagged enums run on BEAM",
                   contains(Binary, <<"#{'$terra_enum' => 'Result', tag => 'Ok'">>) andalso
                   contains(Binary, <<"'$terra_enum' := 'Result', tag := 'Ok'">>) andalso
                   contains(Binary, <<"value := Terra_value_">>));
        Other ->
            io:format("not ok - tagged enums run on BEAM~n  got: ~p~n", [Other]),
            fail
    end.

test_enum_pattern_ignore(OutDir) ->
    Path = "tests/programs/enum_pattern_ignore.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_enum_pattern_ignore, 3, _BeamPath, _ErlangPath} ->
            expect("enum patterns can ignore payloads", true);
        Other ->
            io:format("not ok - enum patterns can ignore payloads~n  got: ~p~n", [Other]),
            fail
    end.

test_pointers(OutDir) ->
    Path = "tests/programs/pointers.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_pointers, Source},
         {ok, terra_pointers, 7, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("temporary-region pointers run and clean up",
                   contains(Binary, <<"terra_region_start(4)">>) andalso
                   contains(Binary, <<"TerraArgsPointer = terra_pointer_new(terra_args(Args))">>) andalso
                   contains(Binary, <<"terra_main_exit(terra_pointer_read(TerraExitPointer))">>) andalso
                   contains(Binary, <<"terra_pointer_write(">>) andalso
                   contains(Binary, <<"terra_pointer_read(">>) andalso
                   contains(Binary, <<"terra_region_already_active">>) andalso
                   contains(Binary, <<"terra_temporary_region_limit">>) andalso
                   erlang:get({terra_pointers, terra_current_region}) == undefined);
        Other ->
            io:format("not ok - temporary-region pointers run and clean up~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_pointer_depth(OutDir) ->
    Path = "tests/programs/pointer_depth.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_pointer_depth, Source},
         {ok, terra_pointer_depth, 7, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("nested and strict pointers run on BEAM",
                   contains(Binary,
                            <<"terra_pointer_new(terra_pointer_new(terra_pointer_new(1)))">>) andalso
                   contains(Binary,
                            <<"terra_pointer_write(terra_pointer_read(terra_pointer_read(">>));
        Other ->
            io:format("not ok - nested and strict pointers run on BEAM~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_pointer_region_overflow(OutDir) ->
    Path = "tests/programs/pointer_region_overflow.terra",
    Result = transpiler:run_file(Path, "", OutDir),
    expect("fixed temporary region enforces capacity",
           is_runtime_reason(Result, {terra_temporary_region_full, 3})).

test_pointer_auto_region(OutDir) ->
    Path = "tests/programs/pointer_auto_region.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_pointer_auto_region, Source},
         {ok, terra_pointer_auto_region, 7, _BeamPath, _ErlangPath}} ->
            expect("automatic temporary region uses compiler estimate",
                   contains(iolist_to_binary(Source),
                            <<"terra_region_start({auto, 3, 65536})">>));
        Other ->
            io:format("not ok - automatic temporary region~n  got: ~p~n", [Other]),
            fail
    end.

test_switch_function_case(OutDir) ->
    Path = "tests/programs/backend_switch_function_case.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_backend_switch_function_case, -100, _BeamPath, _ErlangPath} ->
            expect("switch supports function-call cases", true);
        Other ->
            io:format("not ok - switch supports function-call cases~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_module_declarations(OutDir) ->
    Path = "tests/programs/module_declarations.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_module_declarations, Source},
         {ok, terra_module_declarations, 7, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            expect("module-scope global and const declarations",
                   contains(Binary, <<"Terra_base_">>) andalso
                   contains(Binary, <<"terra_global(\"shared\"">>));
        Other ->
            io:format("not ok - module-scope global and const declarations~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_module_const_priority(OutDir) ->
    Path = "tests/programs/module_const_priority.terra",
    case transpiler:run_file(Path, "ignored args", OutDir) of
        {ok, terra_module_const_priority, 9, _BeamPath, _ErlangPath} ->
            expect("module consts have priority over function bindings", true);
        Other ->
            io:format("not ok - module consts have priority over function bindings~n"
                      "  got: ~p~n", [Other]),
            fail
    end.

test_imports_exports(OutDir) ->
    Path = "tests/programs/imports_exports.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "Ada", OutDir)} of
        {{ok, terra_imports_exports, Source},
         {ok, terra_imports_exports, 5, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            LibBeam = filename:join(OutDir, "terra_math_lib.beam"),
            LibSource = filename:join(OutDir, "terra_math_lib.erl"),
            {ok, LibSourceBinary} = file:read_file(LibSource),
            ErlangAdd = apply(terra_math_lib, 'Add', [4, 5]),
            ErlangLabel = apply(terra_math_lib, 'Label', [<<"ready">>]),
            ErlangPair = apply(terra_math_lib, 'Pair', [<<"score">>, 7]),
            ErlangIncrement = apply(terra_math_lib, 'Increment', [7]),
            BadArgument = erlang_export_error(
                            fun() -> apply(terra_math_lib, 'Add', [<<"bad">>, 5]) end),
            expect("module imports and exports",
                   contains(Binary, <<"terra_math_lib:terra_fn_add">>) andalso
                   contains(LibSourceBinary, <<"'Add'/2">>) andalso
                   filelib:is_file(LibBeam) andalso
                   ErlangAdd == 9 andalso ErlangLabel == <<"ready">> andalso
                   ErlangPair == {<<"score">>, 7} andalso
                   ErlangIncrement == 8 andalso
                   BadArgument ==
                       {invalid_erlang_argument, 'Add', 1, int, <<"bad">>});
        Other ->
            io:format("not ok - module imports and exports~n  got: ~p~n", [Other]),
            fail
    end.

test_std_collection(OutDir) ->
    Path = "tests/programs/std_collection_usage.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "Ada", OutDir)} of
        {{ok, terra_std_collection_usage, Source},
         {ok, terra_std_collection_usage, 9, _BeamPath, _ErlangPath}} ->
            Binary = iolist_to_binary(Source),
            LibBeam = filename:join(OutDir, "terra_std_collection.beam"),
            ErlangLength = apply(terra_std_collection, 'Length', [[1, 2, 3]]),
            ErlangReverse = apply(terra_std_collection, 'Reverse', [[1, 2, 3]]),
            expect("standard library collection module",
                   contains(Binary, <<"terra_std_collection:terra_fn_length">>) andalso
                   filelib:is_file(LibBeam) andalso
                   ErlangLength == 3 andalso
                   ErlangReverse == [3, 2, 1]);
        Other ->
            io:format("not ok - standard library collection module~n  got: ~p~n", [Other]),
            fail
    end.

test_std_helpers(OutDir) ->
    Path = "tests/programs/std_helpers_usage.terra",
    case transpiler:run_file(Path, "Ada", OutDir) of
        {ok, terra_std_helpers_usage, 5, _BeamPath, _ErlangPath} ->
            StringBeam = filename:join(OutDir, "terra_std_string.beam"),
            BinaryBeam = filename:join(OutDir, "terra_std_binary.beam"),
            TimeBeam = filename:join(OutDir, "terra_std_time.beam"),
            RandomBeam = filename:join(OutDir, "terra_std_random.beam"),
            FsBeam = filename:join(OutDir, "terra_std_fs.beam"),
            ErlangTrim = apply(terra_std_string, 'Trim', [<<" Terra ">>]),
            ErlangUpper = apply(terra_std_string, 'Uppercase', [<<"terra">>]),
            ErlangByteSize = apply(terra_std_binary, 'ByteSize', [<<"Terra">>]),
            ErlangIsDir = apply(terra_std_fs, 'IsDir', [<<".">>]),
            Roll = apply(terra_std_random, 'Uniform', [6]),
            expect("standard library practical helper modules",
                   filelib:is_file(StringBeam) andalso
                   filelib:is_file(BinaryBeam) andalso
                   filelib:is_file(TimeBeam) andalso
                   filelib:is_file(RandomBeam) andalso
                   filelib:is_file(FsBeam) andalso
                   ErlangTrim == <<"Terra">> andalso
                   ErlangUpper == <<"TERRA">> andalso
                   ErlangByteSize == 5 andalso
                   ErlangIsDir == true andalso
                   Roll >= 1 andalso Roll =< 6);
        Other ->
            io:format("not ok - standard library practical helper modules~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_std_test(OutDir) ->
    SuccessPath = "tests/programs/std_test_usage.terra",
    FailurePath = "tests/programs/std_test_failure.terra",
    Success = transpiler:run_file(SuccessPath, "pass", OutDir),
    Failure = transpiler:run_file(FailurePath, "actual", OutDir),
    StdTestBeam = filename:join(OutDir, "terra_std_test.beam"),
    ErlangAssert = apply(terra_std_test, 'Assert', [true, <<"passes">>]),
    ErlangFailure = erlang_export_error(
                      fun() -> apply(terra_std_test, 'EqualInt',
                                     [1, 2, <<"int mismatch">>]) end),
    expect("standard library testing assertions",
           Success == {ok, terra_std_test_usage, 0,
                       filename:join(OutDir, "terra_std_test_usage.beam"),
                       filename:join(OutDir, "terra_std_test_usage.erl")} andalso
           is_runtime_reason(Failure,
                             {assertion_failed,
                              <<"argument mismatch actual=actual expected=expected">>}) andalso
           filelib:is_file(StdTestBeam) andalso
           ErlangAssert == ok andalso
           ErlangFailure == {assertion_failed,
                             <<"int mismatch actual=1 expected=2">>}).

erlang_export_error(Fun) ->
    try Fun() of
        _Value -> no_error
    catch
        error:Reason -> Reason
    end.

test_erlang_ffi(OutDir) ->
    Path = "tests/programs/erlang_ffi.terra",
    case {transpiler:transpile_file(Path), transpiler:run_file(Path, "", OutDir)} of
        {{ok, terra_erlang_ffi, Source},
         {ok, terra_erlang_ffi, 6, _BeamPath, _ErlangPath}} ->
            expect("selected Erlang FFI call",
                   contains(iolist_to_binary(Source),
                            <<"terra_ffi_return(number, lists, sum, lists:sum(">>));
        Other ->
            io:format("not ok - selected Erlang FFI call~n  got: ~p~n", [Other]),
            fail
    end.

test_webserver_ffi(OutDir) ->
    Path = "tests/programs/webserver_ffi.terra",
    case transpiler:compile_file(Path, OutDir) of
        {ok, terra_webserver_ffi, _BeamPath, ErlangPath} ->
            {ok, Source} = file:read_file(ErlangPath),
            expect("webserver example compiles Erlang FFI",
                   contains(Source, <<"application:ensure_all_started(inets)">>) andalso
                   contains(Source, <<"inets:start(httpd,">>) andalso
                   contains(Source, <<"inets:stop(httpd,">>));
        Other ->
            io:format("not ok - webserver example compiles Erlang FFI~n  got: ~p~n",
                      [Other]),
            fail
    end.

test_erlang_term_mapping(OutDir) ->
    Path = "tests/programs/erlang_term_mapping.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_erlang_term_mapping, 1, _BeamPath, _ErlangPath} ->
            expect("Terra values map predictably to Erlang terms", true);
        Other ->
            io:format("not ok - Terra values map predictably to Erlang terms~n"
                      "  got: ~p~n", [Other]),
            fail
    end.

test_erlang_return_validation(OutDir) ->
    Path = "tests/programs/erlang_ffi_bad_return.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {error, {runtime_error, error,
                 {invalid_erlang_return, lists, sum, string, 6}, Stacktrace}} ->
            expect("Erlang FFI validates declared return types",
                   has_terra_frame(Stacktrace, Path));
        Other ->
            io:format("not ok - Erlang FFI validates declared return types~n"
                      "  got: ~p~n", [Other]),
            fail
    end.

test_beam_value_types(OutDir) ->
    Path = "tests/programs/beam_value_types.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_beam_value_types, 1, _BeamPath, _ErlangPath} ->
            Pid = self(),
            Ref = make_ref(),
            Bytes = <<0, 255, 1>>,
            Map = #{ready => true},
            expect("Binary, PID, Reference, and Map BEAM types",
                   apply(terra_beam_value_types, 'EchoBinary', [Bytes]) == Bytes andalso
                   apply(terra_beam_value_types, 'EchoPID', [Pid]) == Pid andalso
                   apply(terra_beam_value_types, 'EchoReference', [Ref]) == Ref andalso
                   apply(terra_beam_value_types, 'EchoMap', [Map]) == Map);
        Other ->
            io:format("not ok - Binary, PID, Reference, and Map BEAM types~n"
                      "  got: ~p~n", [Other]),
            fail
    end.

test_process_primitives(OutDir) ->
    Path = "examples/processes.terra",
    case transpiler:run_file(Path, "", OutDir) of
        {ok, terra_processes, 1, _BeamPath, _ErlangPath} ->
            expect("process spawn and message exchange", true);
        Other ->
            io:format("not ok - process spawn and message exchange~n  got: ~p~n", [Other]),
            fail
    end.

test_invalid_process_message(OutDir) ->
    Path = "tests/programs/process_invalid_message.terra",
    case transpiler:compile_file(Path, OutDir) of
        {ok, terra_process_invalid_message, _BeamPath, _ErlangPath} ->
            code:add_pathz(OutDir),
            code:purge(terra_process_invalid_message),
            code:delete(terra_process_invalid_message),
            {module, terra_process_invalid_message} =
                code:load_abs(filename:join(OutDir, "terra_process_invalid_message")),
            self() ! 42,
            Error = erlang_export_error(
                fun() -> apply(terra_process_invalid_message, 'ReadString', []) end),
            expect("received messages are type checked",
                   Error == {invalid_terra_message, string, 42});
        Other ->
            io:format("not ok - received messages are type checked~n  got: ~p~n", [Other]),
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
                      FramePath = proplists:get_value(file, Info),
                      same_source_path(FramePath, Path) andalso
                      proplists:get_value(line, Info, 0) > 0;
                 (_) -> false
              end, Stacktrace).

same_source_path(FramePath, Path) when is_list(FramePath) ->
    FramePath == Path orelse filename:basename(FramePath) == filename:basename(Path);
same_source_path(_FramePath, _Path) -> false.

expect(Name, true) ->
    io:format("ok - ~s~n", [Name]),
    pass;
expect(Name, false) ->
    io:format("not ok - ~s~n", [Name]),
    fail.

contains(Binary, Needle) ->
    binary:match(Binary, Needle) =/= nomatch.
