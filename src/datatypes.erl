-module(datatypes).
-export([all/0, number_types/0, integer_types/0, scalar_types/0,
         aggregate_types/0, text_types/0, beam_handle_types/0, meta_types/0,
         is_type/1, is_builtin/1, is_number_type/1, is_integer_type/1,
         is_scalar_type/1, is_aggregate_type/1, is_text_type/1,
         is_beam_handle_type/1, is_pointer_type/1, is_named_type/1,
         is_constructible/1, crosses_erlang_ffi/1, crosses_process/1,
         normalize/1, display_name/1, type_info/1]).

%% Terra keeps the source language small, but the compiler benefits from a
%% richer type catalog. This table follows the trait-style organization common
%% in modern systems languages: category, construction rules, boundary behavior,
%% and broad capabilities are all explicit metadata.

all() ->
    [number, int, sint, float, atom, bool, map, restricted_map, state, list, tuple,
     string, binary, pid, reference].

number_types() ->
    [int, sint, float].

integer_types() ->
    [int, sint].

scalar_types() ->
    [number, int, sint, float, atom, bool, string, binary].

aggregate_types() ->
    [map, restricted_map, state, list, tuple].

text_types() ->
    [string, binary].

beam_handle_types() ->
    [pid, reference].

meta_types() ->
    [var].

is_type(Type) ->
    is_builtin(normalize(Type)).

is_builtin(Type) ->
    lists:member(Type, all()).

is_number_type(Type) ->
    lists:member(normalize(Type), [number | number_types()]).

is_integer_type(Type) ->
    lists:member(normalize(Type), integer_types()).

is_scalar_type(Type) ->
    lists:member(normalize(Type), scalar_types()).

is_aggregate_type(Type) ->
    lists:member(normalize(Type), aggregate_types()).

is_text_type(Type) ->
    lists:member(normalize(Type), text_types()).

is_beam_handle_type(Type) ->
    lists:member(normalize(Type), beam_handle_types()).

is_pointer_type({pointer, _Type}) -> true;
is_pointer_type({strict_pointer, _Type}) -> true;
is_pointer_type(_Type) -> false.

is_named_type({named, _Name}) -> true;
is_named_type(_Type) -> false.

is_constructible(Type) ->
    maps:get(constructible, type_info(Type), false).

crosses_erlang_ffi(Type) ->
    maps:get(erlang_ffi, type_info(Type), false).

crosses_process(Type) ->
    maps:get(process_message, type_info(Type), false).

normalize(Type) when is_atom(Type) ->
    Type;
normalize({pointer, Type}) ->
    {pointer, normalize(Type)};
normalize({strict_pointer, Type}) ->
    {strict_pointer, normalize(Type)};
normalize({named, Name}) ->
    {named, Name};
normalize(Type) ->
    Type.

display_name(Type) ->
    lists:flatten(display(normalize(Type))).

type_info(number) ->
    primitive(number, numeric, #{children => number_types(),
                                constructible => true,
                                capabilities => [numeric, comparable, orderable]});
type_info(int) ->
    primitive(int, numeric, #{constructible => true,
                             capabilities => [integer, numeric, comparable, orderable,
                                              non_negative]});
type_info(sint) ->
    primitive(sint, numeric, #{constructible => true,
                              capabilities => [integer, numeric, comparable, orderable,
                                               signed]});
type_info(float) ->
    primitive(float, numeric, #{constructible => true,
                               capabilities => [numeric, comparable, orderable,
                                                fractional]});
type_info(atom) ->
    primitive(atom, scalar, #{constructible => true,
                             capabilities => [comparable, symbolic]});
type_info(bool) ->
    primitive(bool, scalar, #{constructible => true,
                             capabilities => [boolean, comparable]});
type_info(string) ->
    primitive(string, text, #{constructible => true,
                             capabilities => [utf8, comparable, orderable, sized]});
type_info(binary) ->
    primitive(binary, text, #{constructible => false,
                             capabilities => [bytes, comparable, sized]});
type_info(list) ->
    primitive(list, aggregate, #{constructible => true,
                                capabilities => [sequence, iterable, sized]});
type_info(tuple) ->
    primitive(tuple, aggregate, #{constructible => true,
                                 capabilities => [product, iterable, sized]});
type_info(map) ->
    primitive(map, aggregate, #{constructible => true,
                               capabilities => [associative, iterable, sized]});
type_info(restricted_map) ->
    primitive(restricted_map, aggregate, #{constructible => true,
                                          capabilities => [associative, bounded,
                                                           iterable, sized]});
type_info(state) ->
    primitive(state, aggregate, #{constructible => true,
                                 capabilities => [associative, iterable, sized,
                                                  state_snapshot]});
type_info(pid) ->
    primitive(pid, beam_handle, #{constructible => false,
                                 capabilities => [opaque, process_handle]});
type_info(reference) ->
    primitive(reference, beam_handle, #{constructible => false,
                                       capabilities => [opaque, unique_handle]});
type_info(var) ->
    meta(var, inference_placeholder);
type_info({pointer, Type}) ->
    pointer(pointer, Type, false);
type_info({strict_pointer, Type}) ->
    pointer(strict_pointer, Type, true);
type_info({named, Name}) ->
    #{kind => named, name => Name, category => user_defined,
      display => Name, constructible => true, erlang_ffi => true,
      process_message => true, capabilities => [comparable, tagged_data]};
type_info(Type) ->
    #{kind => unknown, type => Type, category => unknown,
      display => io_lib:format("~p", [Type]), constructible => false,
      erlang_ffi => false, process_message => false, capabilities => []}.

primitive(Kind, Category, Extra) ->
    Base = #{kind => Kind, category => Category, display => display_name(Kind),
             erlang_ffi => true, process_message => true},
    maps:merge(Base, Extra).

meta(Kind, Role) ->
    #{kind => Kind, category => meta, role => Role, display => display_name(Kind),
      constructible => false, erlang_ffi => false, process_message => false,
      capabilities => []}.

pointer(Kind, Type, Strict) ->
    Normal = normalize(Type),
    #{kind => Kind, pointee => Normal, strict => Strict,
      category => pointer, display => display_name(Kind),
      constructible => true, erlang_ffi => false, process_message => false,
      capabilities => [temporary_region, dereference, writable_slot]}.

display({pointer, Type}) ->
    ["*", display(Type)];
display({strict_pointer, Type}) ->
    ["strict *", display(Type)];
display({named, Name}) ->
    Name;
display(number) -> "Number";
display(int) -> "Int";
display(sint) -> "SInt";
display(float) -> "Float";
display(atom) -> "Atom";
display(bool) -> "Bool";
display(map) -> "Map";
display(restricted_map) -> "RestrictedMap";
display(list) -> "List";
display(tuple) -> "Tuple";
display(string) -> "String";
display(binary) -> "Binary";
display(pid) -> "PID";
display(reference) -> "Reference";
display(var) -> "Var";
display(state) -> "State";
display(Type) when is_atom(Type) -> atom_to_list(Type);
display(Type) -> io_lib:format("~p", [Type]).
