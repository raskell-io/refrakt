-module(refrakt_dev_ffi).
-export([run_dev/0]).

run_dev() ->
    os:putenv("APP_ENV", "dev"),
    %% Check if fswatch is available for file watching
    case os:find_executable("fswatch") of
        false ->
            %% No fswatch — just run gleam run directly
            io:format("Running gleam run (no file watcher found)~n"),
            io:format("Install fswatch for auto-reload: brew install fswatch~n~n"),
            Port = open_port({spawn, "gleam run"}, [stream, exit_status, use_stdio, stderr_to_stdout]),
            relay_and_wait(Port);
        _ ->
            %% fswatch available — run with auto-restart on changes
            io:format("Watching src/ for changes (fswatch)~n~n"),
            run_with_watch()
    end.

run_with_watch() ->
    %% Start gleam run
    AppPort = open_port({spawn, "gleam run"}, [stream, exit_status, use_stdio, stderr_to_stdout]),
    %% Start fswatch on src/ directory
    WatchPort = open_port({spawn, "fswatch -1 -r src/"}, [stream, exit_status, use_stdio]),
    watch_loop(AppPort, WatchPort).

watch_loop(AppPort, WatchPort) ->
    receive
        {AppPort, {data, Data}} ->
            io:put_chars(Data),
            watch_loop(AppPort, WatchPort);
        {WatchPort, {data, _Data}} ->
            %% File changed — kill app, rebuild, restart
            io:format("~n--- File changed, rebuilding... ---~n~n"),
            catch port_close(AppPort),
            timer:sleep(200),
            %% Rebuild
            os:cmd("gleam build"),
            %% Restart
            NewAppPort = open_port({spawn, "gleam run"}, [stream, exit_status, use_stdio, stderr_to_stdout]),
            NewWatchPort = open_port({spawn, "fswatch -1 -r src/"}, [stream, exit_status, use_stdio]),
            watch_loop(NewAppPort, NewWatchPort);
        {WatchPort, {exit_status, _}} ->
            %% fswatch exited (got a change), restart it
            NewWatchPort = open_port({spawn, "fswatch -1 -r src/"}, [stream, exit_status, use_stdio]),
            watch_loop(AppPort, NewWatchPort);
        {AppPort, {exit_status, Status}} ->
            io:format("~nServer exited with status ~p~n", [Status]),
            catch port_close(WatchPort),
            nil;
        _ ->
            watch_loop(AppPort, WatchPort)
    end.

relay_and_wait(Port) ->
    receive
        {Port, {data, Data}} ->
            io:put_chars(Data),
            relay_and_wait(Port);
        {Port, {exit_status, _Status}} ->
            nil;
        _ ->
            relay_and_wait(Port)
    end.
