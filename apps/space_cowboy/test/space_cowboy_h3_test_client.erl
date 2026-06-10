-module(space_cowboy_h3_test_client).

-export([
    get/2,
    get_ok/2,
    get_with_signals/3,
    header/2,
    percent_encode/1
]).

-define(H3_TIMEOUT, 5000).

get_with_signals(Port, Path, Signals) ->
    Json = iolist_to_binary(json:encode(Signals)),
    get_ok(Port, <<Path/binary, "?datastar=", (percent_encode(Json))/binary>>).

get_ok(Port, Path) ->
    {ok, Result} = get(Port, Path),
    Result.

get(Port, Path) ->
    case quicer:connect("localhost", Port, h3_conn_opts(), ?H3_TIMEOUT) of
        {ok, Conn} ->
            try
                h3_request(Conn, Port, Path)
            after
                _ = quicer:close_connection(Conn)
            end;
        Error ->
            Error
    end.

header(Name, Headers) ->
    LowerName = string:lowercase(binary_to_list(Name)),
    Normalized = [{string:lowercase(binary_to_list(Key)), Value} || {Key, Value} <- Headers],
    case lists:keyfind(LowerName, 1, Normalized) of
        {_, Value} -> Value;
        false -> undefined
    end.

percent_encode(Binary) ->
    iolist_to_binary([percent_encode_byte(Byte) || <<Byte>> <= Binary]).

h3_conn_opts() ->
    [
        {alpn, ["h3"]},
        {verify, none},
        {peer_unidi_stream_count, 3},
        {peer_bidi_stream_count, 100}
    ].

h3_request(Conn, Port, Path) ->
    {ok, HTTP3Machine0} = h3_client_preface(Conn),
    {ok, StreamRef} = quicer:start_stream(Conn, #{active => true}),
    {ok, StreamID} = quicer:get_stream_id(StreamRef),
    put({quicer_stream, StreamID}, StreamRef),
    HTTP3Machine1 = cow_http3_machine:init_bidi_stream(StreamID, <<"GET">>, HTTP3Machine0),
    PseudoHeaders = #{
        method => <<"GET">>,
        scheme => <<"https">>,
        authority => iolist_to_binary(["localhost:", integer_to_list(Port)]),
        path => Path
    },
    {ok, fin, HeaderBlock, Instructions, HTTP3Machine2} =
        cow_http3_machine:prepare_headers(StreamID, HTTP3Machine1, fin, PseudoHeaders, []),
    ok = h3_send_instructions(Conn, Instructions),
    ok = cowboy_quicer:send(Conn, StreamID, cow_http3:headers(HeaderBlock), fin),
    h3_recv(Conn, HTTP3Machine2, #{stream_id => StreamID, headers => [], body => <<>>, unidi => #{}}).

h3_client_preface(Conn) ->
    {ok, SettingsBin, HTTP3Machine0} = cow_http3_machine:init(client, #{}),
    {ok, ControlID} = cowboy_quicer:start_unidi_stream(Conn, [<<0>>, SettingsBin]),
    {ok, EncoderID} = cowboy_quicer:start_unidi_stream(Conn, <<2>>),
    {ok, DecoderID} = cowboy_quicer:start_unidi_stream(Conn, <<3>>),
    put(h3_encoder_id, EncoderID),
    put(h3_decoder_id, DecoderID),
    HTTP3Machine = cow_http3_machine:init_unidi_local_streams(ControlID, EncoderID, DecoderID, HTTP3Machine0),
    {ok, HTTP3Machine}.

h3_recv(Conn, HTTP3Machine, State = #{stream_id := StreamID}) ->
    receive
        Msg when is_tuple(Msg), tuple_size(Msg) >= 1, element(1, Msg) =:= quic ->
            case cowboy_quicer:handle(Msg) of
                {stream_started, NewStreamID, unidi} ->
                    HTTP3Machine1 = cow_http3_machine:init_unidi_stream(NewStreamID, unidi_remote, HTTP3Machine),
                    h3_recv(Conn, HTTP3Machine1, put_unidi(NewStreamID, undefined, State));
                {stream_started, NewStreamID, bidi} ->
                    HTTP3Machine1 = cow_http3_machine:init_bidi_stream(NewStreamID, HTTP3Machine),
                    h3_recv(Conn, HTTP3Machine1, State);
                {data, StreamID, fin, Data} ->
                    case h3_parse_data(Conn, StreamID, fin, Data, HTTP3Machine, State) of
                        {ok, _HTTP3Machine1, State1} ->
                            {ok, {maps:get(status, State1), maps:get(headers, State1), maps:get(body, State1)}};
                        {continue, HTTP3Machine1, State1} ->
                            h3_recv(Conn, HTTP3Machine1, State1)
                    end;
                {data, DataStreamID, IsFin, Data} ->
                    {HTTP3Machine1, State1} = h3_parse_data_continue(Conn, DataStreamID, IsFin, Data, HTTP3Machine, State),
                    h3_recv(Conn, HTTP3Machine1, State1);
                {stream_closed, StreamID, _ErrorCode} ->
                    {ok, {maps:get(status, State), maps:get(headers, State), maps:get(body, State)}};
                closed ->
                    {error, closed};
                _ ->
                    h3_recv(Conn, HTTP3Machine, State)
            end
    after ?H3_TIMEOUT ->
        {error, timeout}
    end.

h3_parse_data_continue(Conn, StreamID, IsFin, Data, HTTP3Machine, State) ->
    case h3_parse_data(Conn, StreamID, IsFin, Data, HTTP3Machine, State) of
        {ok, HTTP3Machine1, State1} -> {HTTP3Machine1, State1};
        {continue, HTTP3Machine1, State1} -> {HTTP3Machine1, State1}
    end.

h3_parse_data(Conn, StreamID, IsFin, Data, HTTP3Machine, State = #{stream_id := StreamID}) ->
    h3_parse_frames(Conn, StreamID, IsFin, Data, HTTP3Machine, State);
h3_parse_data(Conn, StreamID, IsFin, Data, HTTP3Machine, State) ->
    case unidi_type(StreamID, State) of
        undefined ->
            case cow_http3:parse_unidi_stream_header(Data) of
                {ok, Type, Rest} ->
                    {ok, HTTP3Machine1} = cow_http3_machine:set_unidi_remote_stream_type(StreamID, Type, HTTP3Machine),
                    h3_parse_unidi(Conn, StreamID, Type, IsFin, Rest, HTTP3Machine1, put_unidi(StreamID, Type, State));
                {undefined, _Rest} ->
                    {continue, HTTP3Machine, put_unidi(StreamID, ignored, State)};
                more ->
                    {continue, HTTP3Machine, State}
            end;
        ignored ->
            {continue, HTTP3Machine, State};
        Type ->
            h3_parse_unidi(Conn, StreamID, Type, IsFin, Data, HTTP3Machine, State)
    end.

h3_parse_unidi(_Conn, _StreamID, _Type, _IsFin, <<>>, HTTP3Machine, State) ->
    {continue, HTTP3Machine, State};
h3_parse_unidi(Conn, StreamID, control, IsFin, Data, HTTP3Machine, State) ->
    h3_parse_frames(Conn, StreamID, IsFin, Data, HTTP3Machine, State);
h3_parse_unidi(Conn, StreamID, Type, IsFin, Data, HTTP3Machine, State) when Type =:= encoder; Type =:= decoder ->
    case cow_http3_machine:unidi_data(Data, IsFin, StreamID, HTTP3Machine) of
        {ok, Instructions, HTTP3Machine1} ->
            ok = h3_send_instructions(Conn, Instructions),
            {continue, HTTP3Machine1, State};
        {error, Error, _HTTP3Machine1} ->
            {continue, HTTP3Machine, State#{error => Error}}
    end.

h3_parse_frames(_Conn, _StreamID, _IsFin, <<>>, HTTP3Machine, State) ->
    {continue, HTTP3Machine, State};
h3_parse_frames(Conn, StreamID, IsFin, Data, HTTP3Machine, State) ->
    case cow_http3:parse(Data) of
        {ok, Frame, Rest} ->
            FrameFin = case Rest of
                <<>> -> IsFin;
                _ -> nofin
            end,
            case cow_http3_machine:frame(Frame, FrameFin, StreamID, HTTP3Machine) of
                {ok, HTTP3Machine1} ->
                    h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine1, State);
                {ok, {data, Body}, HTTP3Machine1} ->
                    State1 = State#{body => <<(maps:get(body, State))/binary, Body/binary>>},
                    h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine1, State1);
                {ok, {headers, Headers, #{status := Status}, _Len}, Instructions, HTTP3Machine1} ->
                    ok = h3_send_instructions(Conn, Instructions),
                    State1 = State#{status => Status, headers => Headers},
                    h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine1, State1);
                {ok, {_Other, _Value}, HTTP3Machine1} ->
                    h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine1, State);
                {error, Error, HTTP3Machine1} ->
                    {continue, HTTP3Machine1, State#{error => Error}};
                {error, Error, Instructions, HTTP3Machine1} ->
                    ok = h3_send_instructions(Conn, Instructions),
                    {continue, HTTP3Machine1, State#{error => Error}}
            end;
        {ignore, Rest} ->
            h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine, State);
        {more, _More, _Needed} ->
            {continue, HTTP3Machine, State};
        more ->
            {continue, HTTP3Machine, State}
    end.

h3_send_instructions(_Conn, undefined) ->
    ok;
h3_send_instructions(Conn, {encoder_instructions, Data}) ->
    cowboy_quicer:send(Conn, get(h3_encoder_id), Data);
h3_send_instructions(Conn, {decoder_instructions, Data}) ->
    cowboy_quicer:send(Conn, get(h3_decoder_id), Data).

unidi_type(StreamID, #{unidi := Unidi}) ->
    maps:get(StreamID, Unidi, undefined).

put_unidi(StreamID, Type, State = #{unidi := Unidi}) ->
    State#{unidi => Unidi#{StreamID => Type}}.

percent_encode_byte(Byte)
    when Byte >= $a, Byte =< $z;
         Byte >= $A, Byte =< $Z;
         Byte >= $0, Byte =< $9;
         Byte =:= $-;
         Byte =:= $.;
         Byte =:= $_;
         Byte =:= $~ ->
    Byte;
percent_encode_byte(Byte) ->
    <<"%", (hex_digit(Byte bsr 4)), (hex_digit(Byte band 16#0F))>>.

hex_digit(N) when N < 10 ->
    $0 + N;
hex_digit(N) ->
    $A + (N - 10).
