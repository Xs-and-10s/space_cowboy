-module(data_starship_adr_tests).

-include_lib("eunit/include/eunit.hrl").

sse_headers_adr_golden_test() ->
    ?assertEqual(#{
        <<"cache-control">> => <<"no-cache">>,
        <<"content-type">> => <<"text/event-stream">>,
        <<"connection">> => <<"keep-alive">>
    }, data_starship:sse_headers()).

send_event_order_adr_golden_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "id: evt-123\n"
          "retry: 2000\n"
          "data: selector #feed\n"
          "data: elements <article id=\"one\">One</article>\n"
          "data: elements <article id=\"two\">Two</article>\n\n">>,
        iolist_to_binary(data_starship:event(
            datastar_patch_elements,
            [
                <<"selector #feed">>,
                <<"elements <article id=\"one\">One</article>">>,
                <<"elements <article id=\"two\">Two</article>">>
            ],
            #{event_id => <<"evt-123">>, retry_duration => 2000}
        ))
    ).

send_event_elides_default_retry_adr_golden_test() ->
    Event = iolist_to_binary(data_starship:event(
        datastar_patch_signals,
        [<<"signals {\"ready\":true}">>],
        #{retry_duration => 1000}
    )),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"ready\":true}\n\n">>,
        Event
    ),
    ?assertEqual(nomatch, binary:match(Event, <<"retry: 1000\n">>)).

patch_elements_minimal_adr_golden_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: elements <div id=\"message\">Hello</div>\n\n">>,
        iolist_to_binary(data_starship:patch_elements(<<"<div id=\"message\">Hello</div>">>))
    ).

patch_elements_all_options_adr_golden_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "id: evt-123\n"
          "retry: 2000\n"
          "data: selector #feed\n"
          "data: mode inner\n"
          "data: useViewTransition true\n"
          "data: namespace svg\n"
          "data: viewTransitionSelector #feed\n"
          "data: elements <g id=\"one\">\n"
          "data: elements <circle></circle>\n"
          "data: elements </g>\n\n">>,
        iolist_to_binary(data_starship:patch_elements(
            <<"<g id=\"one\">\n<circle></circle>\n</g>">>,
            [
                {selector, <<"#feed">>},
                {mode, inner},
                {use_view_transition, true},
                {namespace, svg},
                {view_transition_selector, <<"#feed">>},
                {event_id, <<"evt-123">>},
                {retry_duration, 2000}
            ]
        ))
    ).

patch_elements_remove_adr_golden_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #feed, #otherid\n"
          "data: mode remove\n\n">>,
        iolist_to_binary(data_starship:patch_elements(undefined, #{
            selector => <<"#feed, #otherid">>,
            mode => remove
        }))
    ).

patch_signals_minimal_adr_golden_test() ->
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"output\":\"Patched Output Test\",\"show\":true,\"input\":\"Test\",\"user\":{\"name\":\"\",\"email\":\"\"}}\n\n">>,
        iolist_to_binary(data_starship:patch_signals(
            <<"{\"output\":\"Patched Output Test\",\"show\":true,\"input\":\"Test\",\"user\":{\"name\":\"\",\"email\":\"\"}}">>
        ))
    ).

patch_signals_all_options_adr_golden_test() ->
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "id: evt-123\n"
          "retry: 2000\n"
          "data: onlyIfMissing true\n"
          "data: signals {\"user\":{\"name\":\"Johnny\",\"email\":null,\"preferences\":{\"theme\":\"dark\"}}}\n\n">>,
        iolist_to_binary(data_starship:patch_signals(
            <<"{\"user\":{\"name\":\"Johnny\",\"email\":null,\"preferences\":{\"theme\":\"dark\"}}}">>,
            #{
                only_if_missing => true,
                event_id => <<"evt-123">>,
                retry_duration => 2000
            }
        ))
    ).

execute_script_minimal_adr_golden_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector body\n"
          "data: mode append\n"
          "data: elements <script data-effect=\"el.remove()\">window.ready = true;</script>\n\n">>,
        iolist_to_binary(data_starship:execute_script(<<"window.ready = true;">>))
    ).

execute_script_all_options_adr_golden_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "id: evt-123\n"
          "retry: 2000\n"
          "data: selector body\n"
          "data: mode append\n"
          "data: elements <script type=\"module\" nonce=\"abc123\">import('/app.js');</script>\n\n">>,
        iolist_to_binary(data_starship:execute_script(
            <<"import('/app.js');">>,
            #{
                auto_remove => false,
                attributes => [<<"type=\"module\"">>, <<"nonce=\"abc123\"">>],
                event_id => <<"evt-123">>,
                retry_duration => 2000
            }
        ))
    ).

read_signals_get_adr_golden_test() ->
    ?assertEqual(
        {ok, #{<<"input">> => <<"Test">>, <<"show">> => true}},
        data_starship:read_signals(
            <<"GET">>,
            <<"other=1&datastar=%7B%22input%22%3A%22Test%22%2C%22show%22%3Atrue%7D">>,
            <<>>
        )
    ).

read_signals_body_adr_golden_test() ->
    ?assertEqual(
        {ok, #{<<"input">> => <<"Test">>, <<"show">> => true}},
        data_starship:read_signals(
            <<"PATCH">>,
            <<>>,
            <<"{\"input\":\"Test\",\"show\":true}">>
        )
    ).
