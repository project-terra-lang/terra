#!/usr/bin/env escript

main(_Args) ->
    Cases = [{"help", "escript main.escript help", 0, "Usage:"},
             {"version", "escript main.escript version", 0, "terra 0.1.0"},
             {"types", "escript main.escript types", 0, "SInt"},
             {"check ok", "escript main.escript check tests/programs/main_ok.terra", 0, "ok"},
             {"default check", "escript main.escript tests/programs/main_ok.terra", 0, "ok"},
             {"function ast", "escript main.escript ast tests/programs/functions.terra", 0,
              "return_types"},
             {"variable error", "escript main.escript check tests/variables/null_rejected.terra", 1,
              "null_not_allowed"},
             {"top level code", "escript main.escript check tests/programs/top_level_code.terra", 1,
              "expected_function_declaration"},
             {"missing entry point", "escript main.escript check tests/programs/missing_main.terra", 1,
              "missing_entry_point"},
             {"invalid entry signature", "escript main.escript check tests/programs/main_bad_signature.terra", 1,
              "invalid_entry_point_signature"}],
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
