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

patch_elements_safe_tuple_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #safe\n"
          "data: elements <strong>Safe</strong>\n\n">>,
        iolist_to_binary(data_starship:patch_elements(
            {safe, [<<"<strong>">>, <<"Safe">>, <<"</strong>">>]},
            #{selector => <<"#safe">>}
        ))
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

remove_elements_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "id: rm-1\n"
          "data: selector #toast\n"
          "data: mode remove\n\n">>,
        iolist_to_binary(data_starship:remove_elements(<<"#toast">>, #{event_id => <<"rm-1">>}))
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

remove_signals_test() ->
    Event = iolist_to_binary(data_starship:remove_signals(
        [<<"user.name">>, <<"user.email">>, <<"session">>]
    )),
    {ok, Json} = extract_single_data_value(<<"signals">>, Event),
    ?assertEqual(#{
        <<"session">> => null,
        <<"user">> => #{
            <<"email">> => null,
            <<"name">> => null
        }
    }, json:decode(Json)).

remove_signals_rejects_invalid_path_test() ->
    ?assertError(
        {invalid_signal_path, consecutive_dots, <<"user..name">>},
        iolist_to_binary(data_starship:remove_signals(<<"user..name">>))
    ).

execute_script_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector body\n"
          "data: mode append\n"
          "data: elements <script data-effect=\"el.remove()\">console.log(1)<\\/script></script>\n\n">>,
        iolist_to_binary(data_starship:execute_script(<<"console.log(1)</script>">>))
    ).

execute_script_attribute_map_test() ->
    Event = iolist_to_binary(data_starship:execute_script(<<"import('/app.js')">>, #{
        attributes => #{<<"type">> => <<"module">>, <<"data-value">> => <<"<tag>\"&">>}
    })),
    ?assert(binary:match(Event, <<"data-effect=\"el.remove()\"">>) =/= nomatch),
    ?assert(binary:match(Event, <<"type=\"module\"">>) =/= nomatch),
    ?assert(binary:match(Event, <<"data-value=\"&lt;tag&gt;&quot;&amp;\"">>) =/= nomatch).

redirect_test() ->
    Event = iolist_to_binary(data_starship:redirect(<<"/path?name=O'Reilly">>)),
    ?assert(binary:match(Event, <<"setTimeout(function(){window.location.href=">>) =/= nomatch),
    ?assert(binary:match(Event, <<"\"/path?name=O'Reilly\"">>) =/= nomatch).

console_log_test() ->
    Event = iolist_to_binary(data_starship:console_log(<<"Careful">>, #{level => warn})),
    ?assert(binary:match(Event, <<"console.warn(\"Careful\")">>) =/= nomatch).

action_helpers_test() ->
    ?assertEqual(<<"@post('/counter/increment')">>, iolist_to_binary(data_starship:post(<<"/counter/increment">>))),
    ?assertEqual(
        <<"@delete('/items/42', {retryMaxCount: Infinity})">>,
        iolist_to_binary(data_starship:delete(
            <<"/items/42">>,
            #{options => <<"{retryMaxCount: Infinity}">>}
        ))
    ),
    ?assertEqual(
        <<"@get('/search?q=O\\'Reilly\\\\books')">>,
        iolist_to_binary(data_starship:get(<<"/search?q=O'Reilly\\books">>))
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

read_delete_signals_test() ->
    ?assertEqual(
        {ok, #{<<"id">> => 7}},
        data_starship:read_signals(delete, <<"datastar=%7B%22id%22%3A7%7D">>, <<>>)
    ).

extract_single_data_value(Key, Event) ->
    Prefix = <<"data: ", Key/binary, " ">>,
    Lines = binary:split(Event, <<"\n">>, [global]),
    Matches = [
        binary:part(Line, byte_size(Prefix), byte_size(Line) - byte_size(Prefix))
        || Line <- Lines,
           byte_size(Line) >= byte_size(Prefix),
           binary:part(Line, 0, byte_size(Prefix)) =:= Prefix
    ],
    case Matches of
        [Value] -> {ok, Value};
        _ -> error
    end.
