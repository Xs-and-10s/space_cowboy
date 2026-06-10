-module(space_cowboy_quic_test_logger).

-export([
    emergency/2,
    alert/2,
    critical/2,
    error/2,
    warning/2,
    notice/2,
    info/2,
    debug/2
]).

emergency(_Format, _Args) -> ok.
alert(_Format, _Args) -> ok.
critical(_Format, _Args) -> ok.
error(_Format, _Args) -> ok.
warning(_Format, _Args) -> ok.
notice(_Format, _Args) -> ok.
info(_Format, _Args) -> ok.
debug(_Format, _Args) -> ok.
