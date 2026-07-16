#!/usr/bin/env escript

% Main Entry Point of the Program
main(Args) ->
    code:add_pathz("./ebin"),
    File = file:read_file("first.terra"),
    io:format("~p~n",[File]).