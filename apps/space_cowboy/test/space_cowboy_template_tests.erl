-module(space_cowboy_template_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 100).

attrs_preserve_datastar_names_and_escape_values_test() ->
    Attrs = space_cowboy_html:attrs([
        {<<"data-on:click__prevent">>, <<"@post('/save')">>},
        {<<"data-bind:title">>, true},
        {<<"data-show">>, <<"$open && $count > 0">>},
        {<<"data-attr:aria-label">>, <<"Launch \"now\"">>},
        {<<"hidden">>, false},
        {<<"data-ignore">>, undefined}
    ]),
    ?assertEqual(
        <<" data-on:click__prevent=\"@post(&#39;/save&#39;)\""
          " data-bind:title"
          " data-show=\"$open &amp;&amp; $count &gt; 0\""
          " data-attr:aria-label=\"Launch &quot;now&quot;\"">>,
        iolist_to_binary(Attrs)
    ).

safe_template_html_test() ->
    Fragment = {safe, [
        <<"<button">>,
        space_cowboy_html:attrs([{<<"data-on:click">>, <<"@get('/counter')">>}]),
        <<">Go</button>">>
    ]},
    ?assertEqual(
        {html, [
            <<"<button">>,
            space_cowboy_html:attrs([{<<"data-on:click">>, <<"@get('/counter')">>}]),
            <<">Go</button>">>
        ]},
        space_cowboy_template:html(Fragment)
    ).

safe_template_patch_elements_test() ->
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #target\n"
          "data: mode inner\n"
          "data: elements <strong data-text=\"$title\">Title</strong>\n\n">>,
        iolist_to_binary(space_cowboy_template:patch_elements(
            {safe, <<"<strong data-text=\"$title\">Title</strong>">>},
            #{selector => <<"#target">>, mode => inner}
        ))
    ).

attrs_property_test() ->
    ?assert(proper:quickcheck(prop_attrs_preserve_names_and_escape_values(), proper_opts())).

template_wrappers_property_test() ->
    ?assert(proper:quickcheck(prop_template_wrappers_normalize_to_same_bytes(), proper_opts())).

template_lazy_render_property_test() ->
    ?assert(proper:quickcheck(prop_template_lazy_render_normalizes_to_same_bytes(), proper_opts())).

template_patch_property_test() ->
    ?assert(proper:quickcheck(prop_template_patch_matches_datastar_beam(), proper_opts())).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

prop_attrs_preserve_names_and_escape_values() ->
    ?FORALL(Generated, {datastar_attr_name(), attr_value()},
        begin
            {Name, Value} = Generated,
            Attrs = iolist_to_binary(space_cowboy_html:attrs([{Name, Value}])),
            Expected = <<" ", Name/binary, "=\"", (space_cowboy_html:escape(Value))/binary, "\"">>,
            Attrs =:= Expected
        end).

prop_template_wrappers_normalize_to_same_bytes() ->
    ?FORALL(Iodata, rendered_iodata(),
        begin
            Expected = iolist_to_binary(Iodata),
            iolist_to_binary(space_cowboy_template:to_iodata(Iodata)) =:= Expected
                andalso iolist_to_binary(space_cowboy_template:to_iodata({safe, Iodata})) =:= Expected
                andalso iolist_to_binary(space_cowboy_template:to_iodata({ok, Iodata})) =:= Expected
        end).

prop_template_lazy_render_normalizes_to_same_bytes() ->
    ?FORALL(Iodata, rendered_iodata(),
        begin
            Expected = iolist_to_binary(Iodata),
            Render = fun() -> {safe, Iodata} end,
            iolist_to_binary(space_cowboy_template:to_iodata(Render)) =:= Expected
                andalso space_cowboy_template:html(Render) =:= {html, Iodata}
        end).

prop_template_patch_matches_datastar_beam() ->
    ?FORALL(Generated, {rendered_iodata(), selector(), patch_mode()},
        begin
            {Iodata, Selector, Mode} = Generated,
            Options = #{selector => Selector, mode => Mode},
            iolist_to_binary(space_cowboy_template:patch_elements({safe, Iodata}, Options))
                =:= iolist_to_binary(datastar_beam:patch_elements(Iodata, Options))
        end).

datastar_attr_name() ->
    ?LET(Suffix, non_empty(list(datastar_attr_char())),
        <<"data-", (list_to_binary(Suffix))/binary>>).

datastar_attr_char() ->
    oneof("abcdefghijklmnopqrstuvwxyz0123456789-_:." ).

attr_value() ->
    ?LET(Chars, list(printable_char()), list_to_binary(Chars)).

rendered_iodata() ->
    ?LET(Parts, list(attr_value()), Parts).

selector() ->
    ?LET(Name, non_empty(list(elements("abcdefghijklmnopqrstuvwxyz0123456789-_"))),
        <<"#", (list_to_binary(Name))/binary>>).

patch_mode() ->
    elements([outer, inner, replace, prepend, append, before, 'after', remove]).

printable_char() ->
    oneof(lists:seq(32, 126)).
