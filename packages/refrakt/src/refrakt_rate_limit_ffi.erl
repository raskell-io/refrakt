-module(refrakt_rate_limit_ffi).
-export([system_time_ms/0, system_time_seconds/0]).

system_time_ms() ->
    erlang:system_time(millisecond).

system_time_seconds() ->
    erlang:system_time(second).
