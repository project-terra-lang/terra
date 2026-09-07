#!/usr/bin/env escript

% Main Entry Point of the Program
main(Args) ->
    code:add_pathz("./ebin"),
    run(Args).

run([]) ->
    print_help(),
    ok;
run(["help"]) ->
    print_help(),
    ok;
run(["--help"]) ->
    print_help(),
    ok;
run(["-h"]) ->
    print_help(),
    ok;
run(["version"]) ->
    io:format("terra 0.1.0~n"),
    ok;
run(["--version"]) ->
    io:format("terra 0.1.0~n"),
    ok;
run(["types"]) ->
    print_types(),
    ok;
run(["tokens", Path]) ->
    print_tokens(Path);
run(["ast", Path]) ->
    print_ast(Path);
run(["explain", Path]) ->
    explain_file(Path);
run(["emit", Path]) ->
    emit_file(Path, default_erlang_path(Path));
run(["emit", Path, OutputPath]) ->
    emit_file(Path, OutputPath);
run(["build", Path]) ->
    build_file(Path);
run(["run", Path | ProgramArgs]) ->
    run_file(Path, ProgramArgs);
run(["check", Path]) ->
    check_file(Path);
run([Path]) ->
    check_file(Path);
run([Command | _Args]) ->
    io:format("terra: unknown command '~s'~n~n", [Command]),
    print_help(),
    halt(1).

print_help() ->
    io:format("terra - simple Terra language tool~n~n"),
    io:format("Usage:~n"),
    io:format("  terra <file.terra>          Check a Terra file~n"),
    io:format("  terra check <file.terra>    Check a Terra file~n"),
    io:format("  terra tokens <file.terra>   Print tokenizer output~n"),
    io:format("  terra ast <file.terra>      Print parsed program AST~n"),
    io:format("  terra explain <file.terra>  Explain how a program behaves~n"),
    io:format("  terra emit <file.terra>     Generate Erlang source~n"),
    io:format("  terra build <file.terra>    Compile Erlang source to BEAM~n"),
    io:format("  terra run <file.terra> ...  Build and run Main on the BEAM VM~n"),
    io:format("  terra types                 Print README data types~n"),
    io:format("  terra version               Print version~n"),
    io:format("  terra help                  Print this help~n").

print_types() ->
    io:format("Data Types:~n"),
    print_type_list(datatypes:all()).

print_type_list([]) ->
    ok;
print_type_list([number | Rest]) ->
    io:format("  Number~n"),
    print_number_types(datatypes:number_types()),
    print_type_list(Rest);
print_type_list([Type | Rest]) ->
    io:format("  ~s~n", [display_type(Type)]),
    print_type_list(Rest).

print_number_types([]) ->
    ok;
print_number_types([Type | Rest]) ->
    io:format("    - ~s~n", [display_type(Type)]),
    print_number_types(Rest).

display_type(number) -> "Number";
display_type(int)    -> "Int";
display_type(sint)   -> "SInt";
display_type(float)  -> "Float";
display_type(atom)   -> "Atom";
display_type(bool)   -> "Bool";
display_type(map)    -> "Map";
display_type(restricted_map) -> "RestrictedMap";
display_type(list)   -> "List";
display_type(tuple)  -> "Tuple";
display_type(string) -> "String";
display_type(Type)   -> atom_to_list(Type).

print_tokens(Path) ->
    case tokenizer:tokenize_file(Path) of
        {ok, Tokens} ->
            io:format("~p~n", [Tokens]),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

print_ast(Path) ->
    case program:parse_file(Path) of
        {ok, Ast} ->
            io:format("~p~n", [Ast]),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

explain_file(Path) ->
    case program:parse_file(Path) of
        {ok, Program} ->
            io:put_chars(explainer:format(Program)),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

emit_file(Path, OutputPath) ->
    case transpiler:emit_file(Path, OutputPath) of
        {ok, _Module, WrittenPath} ->
            io:format("terra: wrote Erlang source to ~s~n", [WrittenPath]),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

build_file(Path) ->
    case transpiler:compile_file(Path, build_dir()) of
        {ok, _Module, BeamPath, ErlangPath} ->
            io:format("terra: wrote Erlang source to ~s~n", [ErlangPath]),
            io:format("terra: compiled BEAM module to ~s~n", [BeamPath]),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

run_file(Path, ProgramArgs) ->
    Args = string:join(ProgramArgs, " "),
    case transpiler:run_file(Path, Args, build_dir()) of
        {ok, _Module, Result, _BeamPath, _ErlangPath} ->
            io:format("terra: program returned ~p~n", [Result]),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

default_erlang_path(Path) ->
    Module = atom_to_list(transpiler:module_name(Path)),
    filename:join(build_dir(), Module ++ ".erl").

build_dir() ->
    case os:getenv("TERRA_BUILD_DIR") of
        false -> "terra_build";
        Directory -> Directory
    end.

check_file(Path) ->
    case program:parse_file(Path) of
        {ok, Ast} ->
            print_warnings(Path, maps:get(warnings, Ast, [])),
            io:format("terra: ~s ok~n", [Path]),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

print_warnings(_Path, []) -> ok;
print_warnings(Path, [Warning | Rest]) ->
    io:put_chars(diagnostics:render_warning(Path, Warning)),
    print_warnings(Path, Rest).

print_error(Path, Reason) ->
    io:put_chars(diagnostics:render(Path, Reason)).
