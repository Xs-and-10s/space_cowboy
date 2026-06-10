-module(data_starship_tests).

-include_lib("eunit/include/eunit.hrl").

patch_elements_minimal_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\ndata: elements <div id=\"foo\">Hello</div>\n\n">>,
        iolist_to_binary(data_starship:patch_elements(<<"<div id=\"foo\">Hello</div>">>))
    ).

patch_elements_options_test() ->
    Event = iolist_to_binary(data_starship:patch_elements(
        <<"<li>One</li>\n<li>Two</li>">>,
        #{
            selector => <<"#items">>,
            mode => append,
            namespace => html,
            use_view_transition => true,
            event_id => <<"abc">>,
            retry_duration => 2000
        }
    )),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "id: abc\n"
          "retry: 2000\n"
          "data: selector #items\n"
          "data: mode append\n"
          "data: useViewTransition true\n"
          "data: elements <li>One</li>\n"
          "data: elements <li>Two</li>\n\n">>,
        Event
    ).

patch_elements_remove_without_elements_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #toast\n"
          "data: mode remove\n\n">>,
        iolist_to_binary(data_starship:patch_elements(undefined, #{
            selector => <<"#toast">>,
            mode => remove
        }))
    ).

patch_signals_from_map_test() ->
    Event = iolist_to_binary(data_starship:patch_signals(
        #{<<"hal">> => <<"Affirmative">>, <<"count">> => 1},
        #{only_if_missing => true}
    )),
    ?assertMatch(
        <<"event: datastar-patch-signals\n"
          "data: onlyIfMissing true\n"
          "data: signals ", _/binary>>,
        Event
    ),
    ?assert(binary:match(Event, <<"\"hal\":\"Affirmative\"">>) =/= nomatch),
    ?assert(binary:match(Event, <<"\"count\":1">>) =/= nomatch).

execute_script_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector body\n"
          "data: mode append\n"
          "data: elements <script data-effect=\"el.remove()\">console.log(1)<\\/script></script>\n\n">>,
        iolist_to_binary(data_starship:execute_script(<<"console.log(1)</script>">>))
    ).

read_get_signals_test() ->
    ?assertEqual(
        {ok, #{<<"foo">> => 1}},
        data_starship:read_signals(get, <<"datastar=%7B%22foo%22%3A1%7D">>, <<>>)
    ).

read_get_signals_invalid_query_test() ->
    ?assertEqual(
        {error, invalid_query},
        data_starship:read_signals(get, <<"%">>, <<>>)
    ).

read_post_signals_test() ->
    ?assertEqual(
        {ok, #{<<"foo">> => 1}},
        data_starship:read_signals(post, <<>>, <<"{\"foo\":1}">>)
    ).
