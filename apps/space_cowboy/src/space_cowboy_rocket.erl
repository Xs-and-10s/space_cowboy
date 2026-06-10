%% @doc License-clean helpers for Datastar Pro Rocket integration.
%%
%% This module does not vendor or assume access to Datastar Pro. It only
%% provides server-side conveniences for Rocket's public custom-element and
%% manifest-publishing shape.
-module(space_cowboy_rocket).

-export([
    component/2,
    component/3,
    manifest_endpoint/1,
    manifest_endpoint/2
]).

-type attrs() :: #{iodata() => iodata() | true | false | undefined} | [{iodata(), iodata() | true | false | undefined}].
-type manifest() :: map() | list() | iodata().
-type publish_result() :: ok | {ok, manifest()} | {error, term()} | space_cowboy_handler_return().
-type publish_fun() :: fun((term(), cowboy_req:req()) -> publish_result()).
-type options() :: #{on_publish => publish_fun()}.
-type space_cowboy_handler_return() ::
    {json, iodata()}
    | {reply, non_neg_integer(), #{binary() => iodata()}, iodata()}.

-export_type([attrs/0, manifest/0, options/0, publish_fun/0]).

%% @doc Render a Rocket custom element with no light-DOM children.
-spec component(iodata(), attrs()) -> iodata().
component(Tag, Attrs) ->
    component(Tag, Attrs, <<>>).

%% @doc Render a Rocket custom element with optional light-DOM children.
-spec component(iodata(), attrs(), iodata()) -> iodata().
component(Tag, Attrs, Body) ->
    TagBin = valid_tag(Tag),
    [<<"<">>, TagBin, attrs(Attrs), <<">">>, Body, <<"</">>, TagBin, <<">">>].

%% @doc Build a Space Cowboy route handler for Rocket manifest endpoints.
%%
%% GET returns the configured manifest document as JSON. POST accepts the
%% manifest document published by Rocket and optionally passes the decoded JSON
%% value to an `on_publish' callback.
-spec manifest_endpoint(manifest()) -> fun((cowboy_req:req()) -> space_cowboy_handler_return()).
manifest_endpoint(Manifest) ->
    manifest_endpoint(Manifest, #{}).

-spec manifest_endpoint(manifest(), options()) -> fun((cowboy_req:req()) -> space_cowboy_handler_return()).
manifest_endpoint(Manifest, Options) ->
    fun(Req) -> handle_manifest(cowboy_req:method(Req), Req, Manifest, Options) end.

handle_manifest(<<"GET">>, _Req, Manifest, _Options) ->
    json_reply(200, Manifest);
handle_manifest(<<"HEAD">>, _Req, _Manifest, _Options) ->
    {reply, 200, json_headers(), <<>>};
handle_manifest(<<"POST">>, Req, _Manifest, Options) ->
    case read_json_body(Req) of
        {ok, Published} ->
            publish(Published, Req, Options);
        {error, Reason} ->
            json_reply(400, #{<<"error">> => reason_to_binary(Reason)})
    end;
handle_manifest(_Method, _Req, _Manifest, _Options) ->
    json_reply(405, #{<<"error">> => <<"method_not_allowed">>}).

publish(Published, Req, Options) ->
    case maps:get(on_publish, Options, undefined) of
        undefined ->
            json_reply(202, #{<<"accepted">> => true});
        Fun ->
            normalize_publish_result(Fun(Published, Req))
    end.

normalize_publish_result(ok) ->
    json_reply(202, #{<<"accepted">> => true});
normalize_publish_result({ok, Manifest}) ->
    json_reply(202, Manifest);
normalize_publish_result({error, Reason}) ->
    json_reply(422, #{<<"error">> => reason_to_binary(Reason)});
normalize_publish_result({json, _Body} = Return) ->
    Return;
normalize_publish_result({reply, _Status, _Headers, _Body} = Return) ->
    Return.

read_json_body(Req) ->
    case cowboy_req:read_body(Req) of
        {ok, Body, _Req1} -> decode_json(Body);
        {more, Body, _Req1} -> decode_json(Body)
    end.

decode_json(Body) ->
    try
        {ok, json:decode(Body)}
    catch
        error:Reason -> {error, {invalid_json, Reason}};
        _:Reason -> {error, Reason}
    end.

json_reply(Status, Manifest) ->
    {reply, Status, json_headers(), json_body(Manifest)}.

json_headers() ->
    #{<<"content-type">> => <<"application/json">>}.

json_body(Manifest) when is_map(Manifest) ->
    json:encode(Manifest);
json_body(Manifest) when is_list(Manifest) ->
    case io_lib:printable_list(Manifest) of
        true -> Manifest;
        false -> json:encode(Manifest)
    end;
json_body(Manifest) ->
    Manifest.

attrs(Attrs0) when is_map(Attrs0) ->
    Attrs = lists:sort(normalize_attrs(maps:to_list(Attrs0))),
    space_cowboy_html:attrs(Attrs);
attrs(Attrs) ->
    space_cowboy_html:attrs(normalize_attrs(Attrs)).

normalize_attrs(Attrs) ->
    [{Key, normalize_attr_value(Value)} || {Key, Value} <- Attrs].

normalize_attr_value(true) ->
    true;
normalize_attr_value(false) ->
    false;
normalize_attr_value(undefined) ->
    undefined;
normalize_attr_value(Value) ->
    to_binary(Value).

valid_tag(Tag) ->
    TagBin = to_binary(Tag),
    case binary:match(TagBin, <<"-">>) of
        {_, _} -> TagBin;
        nomatch -> error({invalid_rocket_tag, TagBin})
    end.

reason_to_binary(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason);
reason_to_binary({Reason, _Detail}) when is_atom(Reason) ->
    atom_to_binary(Reason);
reason_to_binary(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value);
to_binary(Value) when is_integer(Value) ->
    integer_to_binary(Value);
to_binary(Value) when is_float(Value) ->
    float_to_binary(Value, [short]);
to_binary(Value) ->
    unicode:characters_to_binary(Value).
