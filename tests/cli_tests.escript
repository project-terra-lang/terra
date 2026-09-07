#!/usr/bin/env escript

main(_Args) ->
    Cases = [{"help", "escript main.escript help", 0, "Usage:"},
             {"version", "escript main.escript version", 0, "terra 0.1.0"},
             {"types", "escript main.escript types", 0, "SInt"},
             {"check ok", "escript main.escript check tests/programs/main_ok.terra", 0, "ok"},
             {"default check", "escript main.escript tests/programs/main_ok.terra", 0, "ok"},
             {"function ast", "escript main.escript ast tests/programs/functions.terra", 0,
              "return_types"},
             {"explain loops", "escript main.escript explain tests/programs/loops.terra", 0,
              "recursive"},
             {"emit Erlang",
              "escript main.escript emit tests/programs/backend_run.terra /tmp/terra_cli_backend.erl",
              0, "wrote Erlang source"},
             {"run on BEAM",
              "TERRA_BUILD_DIR=/tmp/terra_cli_beam escript main.escript run tests/programs/backend_run.terra",
              0, "program returned 7"},
             {"warnings do not fail check",
              "escript main.escript check tests/programs/warnings.terra", 0,
              "[shadowed_variable]"},
             {"runtime error uses Terra source map",
              "TERRA_BUILD_DIR=/tmp/terra_cli_source_map escript main.escript run tests/programs/backend_source_map.terra",
              1, "backend_source_map.terra:3:"},
             {"friendly condition error",
             "escript main.escript check tests/programs/loops_bad_condition.terra", 1,
              "Use a comparison such as x < 10"},
             {"missing return diagnostic",
              "escript main.escript check tests/programs/missing_return.terra", 1,
              "[missing_return]"},
             {"file errors have stable codes",
              "escript main.escript check README.md", 1,
              "[bad_extension]"},
             {"read errors have stable codes",
              "escript main.escript check tests/programs/not_present.terra", 1,
              "[read_failed]"},
             {"try requires a function call",
              "escript main.escript check tests/programs/try_invalid.terra", 1,
              "[try_requires_function_call]"},
             {"unreachable statement diagnostic",
              "escript main.escript check tests/programs/unreachable_after_return.terra", 1,
              "UNREACHABLE STATEMENT"},
             {"duplicate variable diagnostic",
              "escript main.escript check tests/programs/duplicate_multi_binding.terra", 1,
              "DUPLICATE VARIABLE"},
             {"duplicate case diagnostic",
              "escript main.escript check tests/programs/duplicate_case.terra", 1,
              "DUPLICATE CASE"},
             {"invalid shadowing diagnostic",
              "escript main.escript check tests/programs/invalid_loop_shadowing.terra", 1,
              "INVALID SHADOWING"},
             {"void return type diagnostic",
              "escript main.escript check tests/programs/void_return_type.terra", 1,
              "VOID RETURN TYPE"},
             {"missing return type diagnostic",
              "escript main.escript check tests/programs/missing_return_type.terra", 1,
              "Every function must declare a return type"},
             {"multi-value source location",
              "escript main.escript check tests/programs/functions_bad_binding.terra", 1,
              "functions_bad_binding.terra:6:30"},
             {"invalid token diagnostic",
              "escript main.escript check tests/programs/invalid_token.terra", 1,
              "I found the unexpected character '@'"},
             {"variable error", "escript main.escript check tests/variables/null_rejected.terra", 1,
              "NULL NOT ALLOWED"},
             {"top level code", "escript main.escript check tests/programs/top_level_code.terra", 1,
              "EXPECTED FUNCTION DECLARATION"},
             {"top level after slash comment",
              "escript main.escript check tests/programs/top_level_after_slash_comment.terra",
              1, "top_level_after_slash_comment.terra:2:1"},
             {"missing entry point", "escript main.escript check tests/programs/missing_main.terra", 1,
              "MISSING ENTRY POINT"},
             {"invalid entry signature", "escript main.escript check tests/programs/main_bad_signature.terra", 1,
              "INVALID ENTRY POINT SIGNATURE"}],
    Results = [run_case(Case) || Case <- Cases],
    case lists:member(fail, Results) of
        true ->
            io:format("cli tests failed~n"),
            halt(1);
        false ->
            io:format("cli tests passed~n"),
            ok
    end.

run_case({Name, Command, ExpectedCode, ExpectedText}) ->
    OutputPath = "/tmp/terra_cli_test.out",
    FullCommand = Command ++ " > " ++ OutputPath ++ " 2>&1",
    Code = os:cmd(FullCommand ++ "; echo $?"),
    Output = os:cmd("cat " ++ OutputPath),
    ExpectedCodeText = integer_to_list(ExpectedCode),
    case {string:trim(Code), contains(Output, ExpectedText)} of
        {ExpectedCodeText, true} ->
            io:format("ok - ~s~n", [Name]),
            pass;
        Other ->
            io:format("not ok - ~s~n  got: ~p output: ~s~n", [Name, Other, Output]),
            fail
    end.

contains(Text, Needle) ->
    case string:find(Text, Needle) of
        nomatch -> false;
        _ -> true
    end.
