-module(prettyprinter).
-export([print_file/1]).

%% Dump the tokens of a .terra file, one source line per output line.
%%
%% NOTE: this splits the source into lines and tokenizes each line on its own,
%% because tokenize/1 returns a flat token list with no line information.
%% Once tokens carry line numbers, replace this with a group-by over
%% tokenize_file/1 and delete the splitting.
print_file(Path) ->
    case first:check_file_extension(Path) of
        not_match ->
            {error, bad_extension};
        match ->
            case file:read_file(Path) of
                {error, Reason} ->
                    {error, {read_failed, Reason}};
                {ok, Binary} ->
                    Lines = binary:split(Binary, [<<"\n">>], [global]),
                    io:format("[~p,~n", [filename:basename(Path)]),
                    print_lines(Lines),
                    io:format("]~n"),
                    ok
            end
    end.

print_lines([]) ->
    ok;
print_lines([Line | Rest]) ->
    case tokenize_line(Line) of
        {ok, []}       -> ok;                       % blank line or comment only
        {ok, Tokens}   -> io:format("  ~s~n", [format_tokens(Tokens)]);
        {error, Error} -> io:format("  %% ERROR ~p in: ~ts~n", [Error, Line])
    end,
    print_lines(Rest).

%% A bad character on one line shouldn't abort the whole dump.
tokenize_line(Line) ->
    try
        {ok, tokenizer:tokenize(Line)}
    catch
        error:Reason -> {error, Reason}
    end.

format_tokens(Tokens) ->
    lists:join(", ", [io_lib:format("~p", [T]) || T <- Tokens]).