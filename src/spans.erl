-module(spans).
-export([token_kind/1, token_value/1, token_span/1, strip_token/1,
         strip_tokens/1, tokens_span/1, merge/2, from_token_sequence/2,
         unknown/0]).

token_kind({Kind, _Value}) -> Kind;
token_kind({Kind, _Value, _Span}) -> Kind.

token_value({_Kind, Value}) -> Value;
token_value({_Kind, Value, _Span}) -> Value.

token_span({_Kind, _Value, Span}) -> Span;
token_span({_Kind, _Value}) -> unknown().

strip_token({Kind, Value, _Span}) -> {Kind, Value};
strip_token(Token) -> Token.

strip_tokens(Tokens) ->
    [strip_token(Token) || Token <- Tokens].

tokens_span([]) ->
    unknown();
tokens_span(Tokens) ->
    merge(token_span(hd(Tokens)), token_span(last(Tokens))).

merge(#{start := Start}, #{'end' := End}) ->
    #{start => Start, 'end' => End};
merge(_, _) ->
    unknown().

from_token_sequence(_Tokens, []) ->
    unknown();
from_token_sequence(Tokens, LegacySequence) ->
    find_sequence(Tokens, LegacySequence).

unknown() ->
    #{start => #{line => 0, column => 0, offset => 0},
      'end' => #{line => 0, column => 0, offset => 0}}.

last([Item]) -> Item;
last([_ | Rest]) -> last(Rest).

find_sequence([], _LegacySequence) ->
    unknown();
find_sequence([_Token | Rest] = Tokens, LegacySequence) ->
    case starts_with(Tokens, LegacySequence, []) of
        {true, Matched} -> tokens_span(lists:reverse(Matched));
        false -> find_sequence(Rest, LegacySequence)
    end.

starts_with(_Tokens, [], Acc) ->
    {true, Acc};
starts_with([Token | Tokens], [Legacy | LegacyRest], Acc) ->
    case strip_token(Token) == Legacy of
        true -> starts_with(Tokens, LegacyRest, [Token | Acc]);
        false -> false
    end;
starts_with([], _LegacySequence, _Acc) ->
    false.
