#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Expected = [number, int, sint, float, atom, bool, map, list, tuple, string],
    Expected = datatypes:all(),
    [true = datatypes:is_type(Type) || Type <- Expected],
    false = datatypes:is_type(state),
    false = datatypes:is_type(var),
    #{kind := number, children := [int, sint, float]} = datatypes:type_info(number),
    io:format("data type tests passed~n").
