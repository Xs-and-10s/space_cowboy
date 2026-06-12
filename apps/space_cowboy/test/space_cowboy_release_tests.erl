-module(space_cowboy_release_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 25).

app_metadata_golden_test() ->
    DataStarship = app(datastar_beam),
    SpaceCowboy = app(space_cowboy),
    ?assertEqual("0.1.0", prop(vsn, DataStarship)),
    ?assertEqual("0.1.0", prop(vsn, SpaceCowboy)),
    ?assertEqual(["MIT"], prop(licenses, DataStarship)),
    ?assertEqual(["MIT"], prop(licenses, SpaceCowboy)),
    ?assertMatch([{"GitHub", "https://github.com/xs-and-10s/space_cowboy"}], prop(links, DataStarship)),
    ?assertMatch([{"GitHub", "https://github.com/xs-and-10s/space_cowboy"}], prop(links, SpaceCowboy)).

runtime_dependencies_golden_test() ->
    ?assertEqual([kernel, stdlib], prop(applications, app(datastar_beam))),
    SpaceCowboyApps = prop(applications, app(space_cowboy)),
    ?assert(lists:member(kernel, SpaceCowboyApps)),
    ?assert(lists:member(stdlib, SpaceCowboyApps)),
    ?assert(lists:member(cowboy, SpaceCowboyApps)),
    ?assert(lists:member(ranch, SpaceCowboyApps)),
    ?assert(lists:member(datastar_beam, SpaceCowboyApps)).

release_checklist_mentions_publish_boundaries_golden_test() ->
    {ok, Checklist} = file:read_file("docs/release-checklist.md"),
    lists:foreach(fun(Expected) ->
        ?assertMatch({_, _}, binary:match(Checklist, Expected))
    end, [
        <<"datastar_beam">>,
        <<"space_cowboy">>,
        <<".local/">>,
        <<"Datastar Pro">>,
        <<"rebar3 eunit">>,
        <<"rebar3 as quic eunit">>
    ]).

readme_links_release_checklist_golden_test() ->
    {ok, Readme} = file:read_file("README.md"),
    ?assertMatch({_, _}, binary:match(Readme, <<"(docs/release-checklist.md)">>)).

license_is_mit_golden_test() ->
    {ok, License} = file:read_file("LICENSE"),
    ?assertMatch({_, _}, binary:match(License, <<"MIT License">>)).

local_assets_are_ignored_golden_test() ->
    {ok, Gitignore} = file:read_file(".gitignore"),
    ?assertMatch({_, _}, binary:match(Gitignore, <<".local/">>)).

metadata_property_test() ->
    ?assert(proper:quickcheck(prop_app_metadata_is_publishable(), proper_opts())).

prop_app_metadata_is_publishable() ->
    ?FORALL(AppName, elements([datastar_beam, space_cowboy]),
        begin
            Props = app(AppName),
            is_non_empty_string(prop(description, Props))
                andalso valid_semver(prop(vsn, Props))
                andalso prop(licenses, Props) =:= ["MIT"]
                andalso has_github_link(prop(links, Props))
                andalso is_list(prop(applications, Props))
        end).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

app(datastar_beam) ->
    app_props("apps/datastar_beam/src/datastar_beam.app.src", datastar_beam);
app(space_cowboy) ->
    app_props("apps/space_cowboy/src/space_cowboy.app.src", space_cowboy).

app_props(Path, Name) ->
    {ok, [{application, Name, Props}]} = file:consult(Path),
    Props.

prop(Key, Props) ->
    proplists:get_value(Key, Props).

is_non_empty_string(Value) ->
    is_list(Value) andalso Value =/= [].

valid_semver(Value) ->
    case string:split(Value, ".", all) of
        [Major, Minor, Patch] ->
            all_digits(Major) andalso all_digits(Minor) andalso all_digits(Patch);
        _ ->
            false
    end.

all_digits([]) ->
    false;
all_digits(Chars) ->
    lists:all(fun(Char) -> Char >= $0 andalso Char =< $9 end, Chars).

has_github_link(Links) ->
    lists:any(fun
        ({"GitHub", Url}) when is_list(Url) ->
            lists:prefix("https://github.com/", Url);
        (_) ->
            false
    end, Links).
