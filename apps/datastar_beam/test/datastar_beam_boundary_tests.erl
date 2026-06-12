-module(datastar_beam_boundary_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 25).

app_runtime_dependencies_are_server_neutral_golden_test() ->
    ?assertEqual([kernel, stdlib], app_applications()).

public_exports_are_stable_golden_test() ->
    ?assertEqual(expected_public_exports(), public_exports(datastar_beam)).

api_doc_lists_public_exports_golden_test() ->
    {ok, Doc} = file:read_file("docs/datastar-beam-api.md"),
    lists:foreach(fun({Function, Arity}) ->
        Expected = iolist_to_binary([atom_to_binary(Function), <<"/">>, integer_to_binary(Arity)]),
        ?assertMatch({_, _}, binary:match(Doc, Expected))
    end, expected_public_exports()).

does_not_call_adapter_modules_golden_test() ->
    ?assertEqual([], forbidden_remote_calls()).

server_neutral_boundary_property_test() ->
    ?assert(proper:quickcheck(prop_forbidden_modules_are_absent(), proper_opts())).

prop_forbidden_modules_are_absent() ->
    ?FORALL(Module, forbidden_module(),
        not lists:member(Module, app_applications())
            andalso not lists:member(Module, remote_modules(datastar_beam))).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

expected_public_exports() ->
    lists:sort([
        {event, 2},
        {event, 3},
        {execute_script, 1},
        {execute_script, 2},
        {action, 2},
        {action, 3},
        {console_log, 1},
        {console_log, 2},
        {delete, 1},
        {delete, 2},
        {get, 1},
        {get, 2},
        {patch_elements, 1},
        {patch_elements, 2},
        {patch, 1},
        {patch, 2},
        {patch_signals, 1},
        {patch_signals, 2},
        {post, 1},
        {post, 2},
        {put, 1},
        {put, 2},
        {read_signals, 3},
        {redirect, 1},
        {redirect, 2},
        {remove_elements, 1},
        {remove_elements, 2},
        {remove_signals, 1},
        {remove_signals, 2},
        {sse_headers, 0}
    ]).

public_exports(Module) ->
    lists:sort([
        {Function, Arity}
        || {Function, Arity} <- Module:module_info(exports),
           not lists:member({Function, Arity}, [{module_info, 0}, {module_info, 1}])
    ]).

app_applications() ->
    {ok, [{application, datastar_beam, Properties}]} =
        file:consult("apps/datastar_beam/src/datastar_beam.app.src"),
    proplists:get_value(applications, Properties).

forbidden_remote_calls() ->
    RemoteModules = remote_modules(datastar_beam),
    [{Module, Function, Arity} || {Module, Function, Arity} <- remote_calls(datastar_beam),
        lists:member(Module, forbidden_modules()) andalso lists:member(Module, RemoteModules)].

remote_modules(Module) ->
    lists:usort([RemoteModule || {RemoteModule, _Function, _Arity} <- remote_calls(Module)]).

remote_calls(Module) ->
    {ok, {Module, [{abstract_code, {raw_abstract_v1, Forms}}]}} =
        beam_lib:chunks(code:which(Module), [abstract_code]),
    lists:usort(remote_calls_in_terms(Forms)).

remote_calls_in_terms(Term) when is_tuple(Term) ->
    case Term of
        {call, _Line, {remote, _RemoteLine, {atom, _ModuleLine, Module}, {atom, _FunctionLine, Function}}, Args} ->
            [{Module, Function, length(Args)} | remote_calls_in_terms(tuple_to_list(Term))];
        _ ->
            remote_calls_in_terms(tuple_to_list(Term))
    end;
remote_calls_in_terms(Term) when is_list(Term) ->
    lists:append([remote_calls_in_terms(Item) || Item <- Term]);
remote_calls_in_terms(_Term) ->
    [].

forbidden_module() ->
    elements(forbidden_modules()).

forbidden_modules() ->
    [
        cowboy,
        cowboy_req,
        ranch,
        space_cowboy,
        space_cowboy_sse,
        space_cowboy_handler,
        space_cowboy_loop,
        space_cowboy_rocket,
        plug,
        mist,
        elli
    ].
