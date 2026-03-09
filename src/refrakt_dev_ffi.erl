-module(refrakt_dev_ffi).
-export([run_gleam/0]).

run_gleam() ->
    os:putenv("APP_ENV", "dev"),
    Port = open_port({spawn, "gleam run"}, [stream, exit_status, use_stdio, stderr_to_stdout]),
    relay_output(Port).

relay_output(Port) ->
    receive
        {Port, {data, Data}} ->
            io:put_chars(Data),
            relay_output(Port);
        {Port, {exit_status, _Status}} ->
            nil;
        _ ->
            relay_output(Port)
    end.
