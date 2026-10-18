-module(refrakt_cli_dev_test_ffi).
-export([send_change/2, send_change_after/3, flush_changes/1,
         reload_stream_receives/0, reload_server_get/1]).

send_change(Dir, Path) ->
    self() ! {refrakt_dev_change, Dir, [Path]},
    nil.

send_change_after(Ms, Dir, Path) ->
    erlang:send_after(Ms, self(), {refrakt_dev_change, Dir, [Path]}),
    nil.

%% How many change messages arrive within Ms.
flush_changes(Ms) ->
    receive
        {refrakt_dev_change, _, _} -> 1 + flush_changes(Ms)
    after Ms ->
        0
    end.

%% Start the reload server on a free port, subscribe to /events, broadcast
%% a reload and return everything the stream sent.
reload_stream_receives() ->
    {ok, Port} = refrakt_cli_dev_ffi:start_reload_server(0),
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port,
                                   [binary, {active, false}]),
    ok = gen_tcp:send(Socket, <<"GET /events HTTP/1.1\r\nHost: localhost\r\n"
                                "Accept: text/event-stream\r\n\r\n">>),
    Headers = read_until(Socket, <<"retry: 1000\n\n">>, <<>>),
    %% The subscription is asynchronous; give it a moment before
    %% broadcasting.
    timer:sleep(50),
    refrakt_cli_dev_ffi:broadcast_reload(),
    All = read_until(Socket, <<"event: reload\ndata: reload\n\n">>, Headers),
    gen_tcp:close(Socket),
    All.

%% The status line the reload server answers for Path.
reload_server_get(Path) ->
    {ok, Port} = refrakt_cli_dev_ffi:start_reload_server(0),
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port,
                                   [binary, {active, false}]),
    ok = gen_tcp:send(Socket, [<<"GET ">>, Path,
                               <<" HTTP/1.1\r\nHost: localhost\r\n\r\n">>]),
    Response = read_until(Socket, <<"\r\n">>, <<>>),
    gen_tcp:close(Socket),
    [StatusLine | _] = binary:split(Response, <<"\r\n">>),
    StatusLine.

read_until(Socket, Marker, Acc) ->
    case binary:match(Acc, Marker) of
        nomatch ->
            case gen_tcp:recv(Socket, 0, 2000) of
                {ok, Data} -> read_until(Socket, Marker, <<Acc/binary, Data/binary>>);
                {error, Reason} -> <<Acc/binary, (atom_to_binary(Reason))/binary>>
            end;
        _ ->
            Acc
    end.
