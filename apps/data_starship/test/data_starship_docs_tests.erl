-module(data_starship_docs_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 25).
-define(API_DOC, "docs/data-starship-api.md").
-define(TEMPLATING_DOC, "docs/templating.md").

templating_doc_is_linked_from_api_golden_test() ->
    {ok, ApiDoc} = file:read_file(?API_DOC),
    ?assertMatch({_, _}, binary:match(ApiDoc, <<"(templating.md)">>)).

templating_doc_states_core_contract_golden_test() ->
    {ok, Doc} = file:read_file(?TEMPLATING_DOC),
    ?assertMatch({_, _}, binary:match(Doc, <<"Template engines own escaping">>)),
    ?assertMatch({_, _}, binary:match(Doc, <<"data_starship:patch_elements/1,2">>)),
    ?assertMatch({_, _}, binary:match(Doc, <<"does not take dependencies">>)).

templating_doc_covers_expected_engines_golden_test() ->
    {ok, Doc} = file:read_file(?TEMPLATING_DOC),
    lists:foreach(fun(Engine) ->
        ?assertMatch({_, _}, binary:match(Doc, Engine))
    end, expected_engines()).

templating_doc_engines_property_test() ->
    ?assert(proper:quickcheck(prop_templating_doc_mentions_engine(), proper_opts())).

prop_templating_doc_mentions_engine() ->
    {ok, Doc} = file:read_file(?TEMPLATING_DOC),
    ?FORALL(Engine, engine(),
        binary:match(Doc, Engine) =/= nomatch).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

engine() ->
    elements(expected_engines()).

expected_engines() ->
    [<<"HEEx">>, <<"Nakai">>, <<"ErlyDTL">>].
