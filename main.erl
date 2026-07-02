-module(main).
-import(file, [file_read/1]).
-export([start/0]).

start() -> 
    File = file:read_file("first.terra"),
    io:fwrite("~p~n",[File]).