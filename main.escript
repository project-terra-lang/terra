#!/usr/bin/env escript

% Main Entry Point of the Program
main(_Args) ->
    code:add_pathz("./ebin"),
    prettyprinter:print_file("tests/local_var.terra").