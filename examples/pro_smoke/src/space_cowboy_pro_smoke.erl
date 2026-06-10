%% @doc Local-only Datastar Pro smoke app.
%%
%% The licensed Pro files live outside git. This example reads their paths
%% from environment variables, falling back to `.env' for local development.
-module(space_cowboy_pro_smoke).

-export([
    start/0,
    start/2,
    stop/0,
    stop/1,
    load_config/0,
    routes/1,
    home/1
]).

start() ->
    start(space_cowboy_pro_smoke, #{port => 8081}).

start(Name, Options) ->
    application:ensure_all_started(space_cowboy),
    case load_config() of
        {ok, Config} -> space_cowboy:start_clear(Name, routes(Config), Options);
        {error, _Reason} = Error -> Error
    end.

stop() ->
    stop(space_cowboy_pro_smoke).

stop(Name) ->
    space_cowboy:stop(Name).

load_config() ->
    Env = dot_env(),
    case env_path("DATASTAR_PRO_BUNDLE", Env) of
        {ok, BundlePath} ->
            Config0 = #{bundle_path => BundlePath},
            Config = case env_path("DATASTAR_PRO_INSPECTOR", Env) of
                {ok, InspectorPath} -> Config0#{inspector_path => InspectorPath};
                {error, _} -> Config0
            end,
            {ok, Config};
        {error, _} = Error ->
            Error
    end.

routes(Config) ->
    [
        {"/", fun(Req) -> home(Req, Config) end},
        {"/assets/datastar-pro.js", fun(_Req) ->
            asset(maps:get(bundle_path, Config), <<"application/javascript; charset=utf-8">>)
        end},
        {"/assets/datastar-inspector.js", fun(_Req) ->
            case maps:get(inspector_path, Config, undefined) of
                undefined -> {reply, 404, #{<<"content-type">> => <<"text/plain">>}, <<"not found">>};
                InspectorPath -> asset(InspectorPath, <<"application/javascript; charset=utf-8">>)
            end
        end},
        {"/api/rocket/manifests", space_cowboy_rocket:manifest_endpoint(manifest(), #{
            on_publish => fun(Published, _Req) -> {ok, #{<<"received">> => Published}} end
        })}
    ].

home(Req) ->
    case load_config() of
        {ok, Config} -> home(Req, Config);
        {error, Reason} -> {reply, 500, #{<<"content-type">> => <<"text/plain">>}, reason_to_binary(Reason)}
    end.

home(_Req, Config) ->
    Body = [
        <<"<main data-signals='{ \"count\": 5 }'>">>,
        <<"<h1>Datastar Pro Smoke</h1>">>,
        space_cowboy_rocket:component(<<"space-counter">>, #{
            <<"count">> => 5,
            <<"data-label">> => <<"Rocket">>
        }, <<"<p data-text=\"$count\"></p>">>),
        <<"</main>">>
    ],
    {html, page(<<"Datastar Pro Smoke">>, scripts(Config), Body)}.

asset(Path, ContentType) ->
    case file:read_file(Path) of
        {ok, Body} -> {reply, 200, #{<<"content-type">> => ContentType}, Body};
        {error, _Reason} -> {reply, 404, #{<<"content-type">> => <<"text/plain">>}, <<"not found">>}
    end.

page(Title, Scripts, Body) ->
    [
        <<"<!doctype html><html><head><meta charset=\"utf-8\">">>,
        <<"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">">>,
        <<"<title">>, <<">">>, space_cowboy_html:escape(Title), <<"</title>">>,
        Scripts,
        <<"</head><body>">>,
        Body,
        <<"</body></html>">>
    ].

scripts(Config) ->
    [
        space_cowboy:datastar_script(<<"/assets/datastar-pro.js">>),
        case maps:is_key(inspector_path, Config) of
            true -> space_cowboy:datastar_script(<<"/assets/datastar-inspector.js">>);
            false -> []
        end
    ].

manifest() ->
    <<"{\"version\":1,\"components\":[{\"tag\":\"space-counter\"}]}">>.

env_path(Name, Env) ->
    case os:getenv(Name) of
        false ->
            case maps:find(Name, Env) of
                {ok, Path} -> existing_path(Path);
                error -> {error, {missing_env, list_to_binary(Name)}}
            end;
        Path ->
            existing_path(Path)
    end.

existing_path(Path0) ->
    Path = filename:absname(Path0),
    case filelib:is_regular(Path) of
        true -> {ok, Path};
        false -> {error, {missing_file, Path}}
    end.

dot_env() ->
    case file:read_file(".env") of
        {ok, Bytes} -> parse_dot_env(Bytes);
        {error, _} -> #{}
    end.

parse_dot_env(Bytes) ->
    Lines = binary:split(Bytes, <<"\n">>, [global]),
    maps:from_list([Pair || Line <- Lines, Pair <- parse_dot_env_line(Line)]).

parse_dot_env_line(<<"">>) ->
    [];
parse_dot_env_line(<<"#", _/binary>>) ->
    [];
parse_dot_env_line(Line) ->
    case binary:split(Line, <<"=">>) of
        [Key, Value] -> [{binary_to_list(trim(Key)), binary_to_list(unquote(trim(Value)))}];
        _ -> []
    end.

trim(Binary) ->
    trim_left(trim_right(Binary)).

trim_left(<<" ", Rest/binary>>) ->
    trim_left(Rest);
trim_left(<<"\t", Rest/binary>>) ->
    trim_left(Rest);
trim_left(Binary) ->
    Binary.

trim_right(Binary) ->
    Size = byte_size(Binary),
    case Size of
        0 ->
            Binary;
        _ ->
            Last = binary:at(Binary, Size - 1),
            case Last of
                $\s -> trim_right(binary:part(Binary, 0, Size - 1));
                $\t -> trim_right(binary:part(Binary, 0, Size - 1));
                _ -> Binary
            end
    end.

unquote(<<"'", Rest/binary>>) ->
    unquote_suffix(Rest, <<"'">>);
unquote(<<"\"", Rest/binary>>) ->
    unquote_suffix(Rest, <<"\"">>);
unquote(Binary) ->
    Binary.

unquote_suffix(Binary, Quote) ->
    Size = byte_size(Binary),
    case Size > 0 andalso binary:part(Binary, Size - 1, 1) =:= Quote of
        true -> binary:part(Binary, 0, Size - 1);
        false -> Binary
    end.

reason_to_binary(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).
