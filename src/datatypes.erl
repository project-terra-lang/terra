-module(datatypes).
-export([all/0, number_types/0, is_type/1, type_info/1]).

%% Data types from README.md.

all() ->
    [number, int, sint, float, atom, bool, map, list, tuple, string].

number_types() ->
    [int, sint, float].

is_type(Type) ->
    lists:member(Type, all()).

type_info(number) ->
    #{kind => number, children => number_types()};
type_info(Type) ->
    case is_type(Type) of
        true -> #{kind => Type};
        false -> #{kind => unknown, type => Type}
    end.
