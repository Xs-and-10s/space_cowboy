%% @doc Tiny HTML helpers for examples and smoke tests.
%%
%% This is deliberately not a template engine. Space Cowboy should make
%% Temple/HEEx/Lustre/Nitro/etc. easy to use from BEAM languages rather than
%% forcing everyone into one markup DSL.
-module(space_cowboy_html).

-export([page/2, attrs/1, escape/1]).

-spec page(iodata(), iodata()) -> iodata().
page(Title, Body) ->
    [
        <<"<!doctype html><html><head><meta charset=\"utf-8\">">>,
        <<"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">">>,
        <<"<title">>, <<">">>, escape(Title), <<"</title>">>,
        space_cowboy:datastar_script(),
        <<"</head><body>">>,
        Body,
        <<"</body></html>">>
    ].

-spec attrs([{iodata(), iodata() | true | false | undefined}]) -> iodata().
attrs(Attrs) ->
    [[<<" ">>, Key, attr_value(Value)] || {Key, Value} <- Attrs, Value =/= false, Value =/= undefined].

-spec escape(iodata()) -> binary().
escape(Value) ->
    Escaped0 = binary:replace(to_binary(Value), <<"&">>, <<"&amp;">>, [global]),
    Escaped1 = binary:replace(Escaped0, <<"<">>, <<"&lt;">>, [global]),
    Escaped2 = binary:replace(Escaped1, <<">">>, <<"&gt;">>, [global]),
    Escaped3 = binary:replace(Escaped2, <<"\"">>, <<"&quot;">>, [global]),
    binary:replace(Escaped3, <<"'">>, <<"&#39;">>, [global]).

attr_value(true) ->
    <<>>;
attr_value(Value) ->
    [<<"=\"">>, escape(Value), <<"\"">>].

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) ->
    unicode:characters_to_binary(Value).
