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
    io:format("  terra ast <file.terra>      Print parsed variable AST~n"),
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
    case variables:parse_file(Path) of
        {ok, Ast} ->
            io:format("~p~n", [Ast]),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

check_file(Path) ->
    case variables:parse_file(Path) of
        {ok, _Ast} ->
            io:format("terra: ~s ok~n", [Path]),
            ok;
        {error, Reason} ->
            print_error(Path, Reason),
            halt(1)
    end.

print_error(Path, bad_extension) ->
    io:format("terra: ~s: expected a .terra file~n", [Path]);
print_error(Path, {read_failed, Reason}) ->
    io:format("terra: ~s: could not read file: ~p~n", [Path, Reason]);
print_error(Path, Reason) ->
    io:format("terra: ~s: ~p~n", [Path, Reason]).
