%% Process work for `refrakt dev`: the build/restart loop, the file
%% watchers and the live reload event stream. The decisions (which watcher,
%% what a change calls for, what changed between two snapshots) are pure
%% functions in refrakt_cli/dev.gleam.
-module(refrakt_cli_dev_ffi).
-behaviour(gen_event).

-export([run_dev/4, os_family/0, find_executable/1, getenv/1]).
-export([snapshot/1, collect_changes/2, start_reload_server/1,
         broadcast_reload/0]).
%% gen_event callbacks, to stop the app when refrakt dev gets SIGTERM.
-export([init/1, handle_event/2, handle_call/2, handle_info/2,
         terminate/2, code_change/3]).

-define(BROKER, refrakt_cli_dev_reload).
%% A burst of events is cut off after this long, even if events keep coming.
-define(MAX_BURST_MS, 2000).
%% Files larger than this are compared by size and time only when polling.
-define(MAX_HASHED_BYTES, 1048576).

%% ---------------------------------------------------------------------------
%% Small helpers called from Gleam
%% ---------------------------------------------------------------------------

os_family() ->
    {_, Name} = os:type(),
    atom_to_binary(Name).

find_executable(Name) ->
    case os:find_executable(binary_to_list(Name)) of
        false -> {error, nil};
        Path -> {ok, list_to_binary(Path)}
    end.

getenv(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, list_to_binary(Value)}
    end.

%% ---------------------------------------------------------------------------
%% The dev loop
%% ---------------------------------------------------------------------------

run_dev(Watcher, LiveReloadPort, AppPort, DebounceMs) ->
    os:putenv("APP_ENV", "dev"),
    case start_reload_server(LiveReloadPort) of
        {ok, _} ->
            os:putenv("REFRAKT_LIVE_RELOAD_PORT",
                      integer_to_list(LiveReloadPort)),
            io:format("Live reload on http://localhost:~b/events~n",
                      [LiveReloadPort]);
        {error, Reason} ->
            os:unsetenv("REFRAKT_LIVE_RELOAD_PORT"),
            io:format("Live reload is off: cannot listen on port ~b (~p). "
                      "Set REFRAKT_LIVE_RELOAD_PORT to a free port.~n",
                      [LiveReloadPort, Reason])
    end,
    io:format("~n"),
    Main = self(),
    trap_sigterm(Main),
    lists:foreach(fun(Dir) -> start_watcher(Watcher, Dir, Main) end,
                  [D || D <- [<<"src">>, <<"priv">>], filelib:is_dir(D)]),
    State0 = #{app => undefined, app_port => AppPort, gen => 0,
               debounce => DebounceMs, watchers => []},
    State = case build() of
        ok ->
            start_app(State0);
        error ->
            io:format("~n--- Build failed. Fix the error and save to start "
                      "the server. ---~n~n"),
            State0
    end,
    loop(State).

loop(#{app := App, gen := Gen, debounce := Debounce} = State) ->
    receive
        {App, {data, Data}} when App =/= undefined ->
            io:put_chars(Data),
            loop(State);
        {App, {exit_status, Status}} when App =/= undefined ->
            io:format("~n--- Server exited with status ~b. Save a file to "
                      "rebuild and restart it. ---~n~n", [Status]),
            loop(State#{app := undefined});
        {refrakt_dev_change, Dir, Paths} ->
            Changes = collect_changes([{Dir, P} || P <- Paths], Debounce),
            loop(handle_changes('refrakt_cli@dev':classify(Changes), State));
        {app_ready, Gen} ->
            broadcast_reload(),
            loop(State);
        {watcher_os_pid, Pid} ->
            loop(State#{watchers := [Pid | maps:get(watchers, State)]});
        sigterm ->
            stop_app(State),
            kill("TERM", maps:get(watchers, State)),
            erlang:halt(0);
        _ ->
            loop(State)
    end.

handle_changes(no_change, State) ->
    State;
handle_changes(reload_only, State) ->
    io:format("~n--- priv/ changed, reloading open pages ---~n~n"),
    broadcast_reload(),
    State;
handle_changes(rebuild, #{app := App} = State) ->
    io:format("~n--- File changed, rebuilding... ---~n~n"),
    case build() of
        ok ->
            start_app(stop_app(State));
        error when App =:= undefined ->
            io:format("~n--- Build failed. Fix the error and save to start "
                      "the server. ---~n~n"),
            State;
        error ->
            io:format("~n--- Build failed. The previous server keeps "
                      "running; fix the error and save. ---~n~n"),
            State
    end.

%% Run `gleam build`, streaming its output. The running server is left
%% alone, so a failed build changes nothing.
build() ->
    case gleam() of
        false ->
            io:format("Cannot find `gleam` on the PATH.~n"),
            error;
        Gleam ->
            Port = open_port({spawn_executable, Gleam},
                             [{args, ["build"]}, exit_status, binary, stream,
                              stderr_to_stdout]),
            build_loop(Port)
    end.

build_loop(Port) ->
    receive
        {Port, {data, Data}} ->
            io:put_chars(Data),
            build_loop(Port);
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, _}} -> error
    end.

start_app(#{gen := Gen0, app_port := AppPort} = State) ->
    Gen = Gen0 + 1,
    App = open_supervised(gleam(), ["run"],
                          [exit_status, binary, stream, stderr_to_stdout]),
    Main = self(),
    spawn(fun() -> wait_until_listening(Main, Gen, AppPort, 600) end),
    State#{app := App, gen := Gen}.

%% Tell the loop once the new server accepts connections, so pages reload
%% into the new code rather than into a connection error.
wait_until_listening(_Main, _Gen, _AppPort, 0) ->
    ok;
wait_until_listening(Main, Gen, AppPort, Tries) ->
    case accepts_connections(AppPort) of
        true ->
            Main ! {app_ready, Gen};
        false ->
            timer:sleep(100),
            wait_until_listening(Main, Gen, AppPort, Tries - 1)
    end.

accepts_connections(Port) ->
    lists:any(
      fun(Ip) ->
          case gen_tcp:connect(Ip, Port, [], 200) of
              {ok, Socket} -> gen_tcp:close(Socket), true;
              {error, _} -> false
          end
      end,
      [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]).

%% Stop the server: `gleam run` and the Erlang VM it started.
stop_app(#{app := undefined} = State) ->
    State;
stop_app(#{app := App, app_port := AppPort} = State) ->
    Pids = case erlang:port_info(App, os_pid) of
        {os_pid, Pid} -> [Pid | descendants(Pid)];
        undefined -> []
    end,
    kill("TERM", Pids),
    case wait_for_exit(App, 5000) of
        ok -> ok;
        timeout ->
            kill("KILL", Pids),
            wait_for_exit(App, 2000)
    end,
    catch port_close(App),
    wait_until_free(AppPort, 50),
    State#{app := undefined}.

%% The old server's shutdown logs (SIGTERM notice, supervisor reports from
%% the HTTP server's acceptors) are noise here, so they are dropped.
wait_for_exit(App, Timeout) ->
    receive
        {App, {data, _}} ->
            wait_for_exit(App, Timeout);
        {App, {exit_status, _}} ->
            ok
    after Timeout ->
        timeout
    end.

wait_until_free(_Port, 0) ->
    ok;
wait_until_free(Port, Tries) ->
    case accepts_connections(Port) of
        true -> timer:sleep(100), wait_until_free(Port, Tries - 1);
        false -> ok
    end.

descendants(Pid) ->
    Out = os:cmd("pgrep -P " ++ integer_to_list(Pid)),
    Children = [list_to_integer(L) || L <- string:lexemes(Out, "\n"),
                                      L =/= "",
                                      lists:all(fun(C) -> C >= $0 andalso C =< $9 end, L)],
    Children ++ lists:flatmap(fun descendants/1, Children).

kill(_Signal, []) ->
    ok;
kill(Signal, Pids) ->
    Args = lists:join(" ", [integer_to_list(P) || P <- Pids]),
    os:cmd("kill -" ++ Signal ++ " " ++ lists:flatten(Args) ++ " 2>/dev/null"),
    ok.

gleam() ->
    os:find_executable("gleam").

%% Start a long-running program (the server, a watcher) through a small sh
%% wrapper that stops it when refrakt dev goes away. Erlang starts port
%% programs in their own session, so Ctrl-C in the terminal never reaches
%% them; without the wrapper the server would keep the port after
%% refrakt dev exits. The wrapper runs the program in the background,
%% waits for its own stdin (the port's pipe) to close, then stops the
%% program and its children. It passes the program's exit status on.
open_supervised(Executable, Args, Options) ->
    open_port({spawn_executable, "/bin/sh"},
              [{args, ["-c", supervisor_script(), "refrakt-dev",
                       Executable | Args]} | Options]).

supervisor_script() ->
    "exec 3<&0\n"
    "\"$@\" </dev/null &\n"
    "child=$!\n"
    "stop() { pkill -TERM -P \"$child\" 2>/dev/null; kill -TERM \"$child\" 2>/dev/null; }\n"
    "trap 'stop; exit 143' TERM\n"
    "(while read -r _ <&3; do :; done; stop) &\n"
    "reader=$!\n"
    "wait \"$child\"\n"
    "status=$?\n"
    "kill \"$reader\" 2>/dev/null\n"
    "exit \"$status\"\n".

%% ---------------------------------------------------------------------------
%% Debounce
%% ---------------------------------------------------------------------------

%% Collect the change messages that arrive until none has come for
%% WindowMs (or ?MAX_BURST_MS have passed), so a burst of events (an editor
%% writing a file in steps, a `git checkout`) becomes one rebuild.
collect_changes(Changes, WindowMs) ->
    Deadline = erlang:monotonic_time(millisecond) + ?MAX_BURST_MS,
    collect_changes(Changes, WindowMs, Deadline).

collect_changes(Changes, WindowMs, Deadline) ->
    Left = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {refrakt_dev_change, Dir, Paths} ->
            collect_changes(Changes ++ [{Dir, P} || P <- Paths], WindowMs,
                            Deadline)
    after min(WindowMs, Left) ->
        Changes
    end.

%% ---------------------------------------------------------------------------
%% Watchers: each sends {refrakt_dev_change, Dir, Paths} to the loop
%% ---------------------------------------------------------------------------

start_watcher({fswatch, Exe}, Dir, Main) ->
    %% -l 0.1: report after 0.1s instead of fswatch's default 1s.
    spawn(fun() ->
        port_watcher("fswatch", Exe, ["-r", "-l", "0.1", Dir], Dir, Main)
    end);
start_watcher({inotifywait, Exe}, Dir, Main) ->
    spawn(fun() ->
        port_watcher("inotifywait", Exe,
                     ["-m", "-r", "-q", "-e", "modify,create,delete,move",
                      "--format", "%w%f", Dir],
                     Dir, Main)
    end);
start_watcher({polling, Interval}, Dir, Main) ->
    spawn(fun() -> poll(Dir, Main, Interval, snapshot(Dir)) end).

port_watcher(Name, Exe, Args, Dir, Main) ->
    Port = open_supervised(binary_to_list(Exe), Args,
                           [{line, 4096}, exit_status, binary]),
    case erlang:port_info(Port, os_pid) of
        {os_pid, Pid} -> Main ! {watcher_os_pid, Pid};
        undefined -> ok
    end,
    port_watcher_loop(Name, Port, Dir, Main).

port_watcher_loop(Name, Port, Dir, Main) ->
    receive
        {Port, {data, {_, Line}}} ->
            Main ! {refrakt_dev_change, Dir, [Line]},
            port_watcher_loop(Name, Port, Dir, Main);
        {Port, {exit_status, Status}} ->
            io:format("~n~s stopped watching ~s/ (status ~b); polling it "
                      "instead~n", [Name, Dir, Status]),
            poll(Dir, Main, 500, snapshot(Dir))
    end.

poll(Dir, Main, Interval, Before) ->
    timer:sleep(Interval),
    After = snapshot(Dir),
    case 'refrakt_cli@dev':changed_paths(Before, After) of
        [] -> ok;
        Paths -> Main ! {refrakt_dev_change, Dir, Paths}
    end,
    poll(Dir, Main, Interval, After).

%% Every file under Dir with its size, modification time and (for files up
%% to 1 MiB) an MD5 of its contents. File times have one-second resolution,
%% so the hash catches two saves within the same second.
snapshot(Dir) ->
    filelib:fold_files(
      binary_to_list(Dir), ".*", true,
      fun(File, Acc) ->
          case stamp(File) of
              {ok, Stamp} -> maps:put(unicode:characters_to_binary(File),
                                      Stamp, Acc);
              error -> Acc
          end
      end,
      #{}).

stamp(File) ->
    case file:read_file_info(File, [{time, posix}]) of
        {ok, Info} ->
            Size = element(2, Info),
            Mtime = element(6, Info),
            Hash = case Size =< ?MAX_HASHED_BYTES of
                true ->
                    case file:read_file(File) of
                        {ok, Bin} -> erlang:md5(Bin);
                        {error, _} -> none
                    end;
                false -> none
            end,
            {ok, {Size, Mtime, Hash}};
        {error, _} ->
            error
    end.

%% ---------------------------------------------------------------------------
%% Live reload: a Server-Sent Events stream at /events
%% ---------------------------------------------------------------------------

%% Listen on Port on the loopback interfaces. Port 0 picks a free port;
%% the result is the port in use.
start_reload_server(Port) ->
    Options = [binary, {active, false}, {reuseaddr, true}, {packet, raw}],
    case gen_tcp:listen(Port, [{ip, {127, 0, 0, 1}} | Options]) of
        {ok, Listen} ->
            {ok, Bound} = inet:port(Listen),
            ensure_broker(),
            spawn_acceptor(Listen),
            case gen_tcp:listen(Bound, [inet6, {ip, {0, 0, 0, 0, 0, 0, 0, 1}}
                                        | Options]) of
                {ok, Listen6} -> spawn_acceptor(Listen6);
                {error, _} -> ok
            end,
            {ok, Bound};
        {error, Reason} ->
            {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.

spawn_acceptor(Listen) ->
    Acceptor = spawn(fun() -> accept_loop(Listen) end),
    ok = gen_tcp:controlling_process(Listen, Acceptor).

%% Ask every connected page to reload.
broadcast_reload() ->
    case whereis(?BROKER) of
        undefined -> nil;
        Broker -> Broker ! reload, nil
    end.

ensure_broker() ->
    case whereis(?BROKER) of
        undefined ->
            Broker = spawn(fun() -> broker([]) end),
            register(?BROKER, Broker);
        _ ->
            ok
    end.

broker(Clients) ->
    receive
        {subscribe, Pid} ->
            erlang:monitor(process, Pid),
            broker([Pid | Clients]);
        {'DOWN', _, process, Pid, _} ->
            broker(lists:delete(Pid, Clients));
        reload ->
            lists:foreach(fun(Pid) -> Pid ! reload end, Clients),
            broker(Clients)
    end.

accept_loop(Listen) ->
    case gen_tcp:accept(Listen) of
        {ok, Socket} ->
            Client = spawn(fun() -> receive go -> client(Socket) end end),
            case gen_tcp:controlling_process(Socket, Client) of
                ok -> Client ! go;
                {error, _} -> exit(Client, kill), gen_tcp:close(Socket)
            end,
            accept_loop(Listen);
        {error, closed} ->
            ok;
        {error, _} ->
            accept_loop(Listen)
    end.

client(Socket) ->
    case read_request(Socket, <<>>) of
        {ok, <<"GET /events", _/binary>>} ->
            ok = gen_tcp:send(Socket, [
                <<"HTTP/1.1 200 OK\r\n">>,
                <<"Content-Type: text/event-stream\r\n">>,
                <<"Cache-Control: no-cache\r\n">>,
                <<"Access-Control-Allow-Origin: *\r\n">>,
                <<"Connection: keep-alive\r\n\r\n">>,
                <<"retry: 1000\n\n">>
            ]),
            ?BROKER ! {subscribe, self()},
            event_loop(Socket);
        {ok, _} ->
            gen_tcp:send(Socket, <<"HTTP/1.1 404 Not Found\r\n"
                                   "Content-Length: 0\r\n"
                                   "Connection: close\r\n\r\n">>),
            gen_tcp:close(Socket);
        error ->
            gen_tcp:close(Socket)
    end.

read_request(Socket, Acc) ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        nomatch when byte_size(Acc) > 16384 ->
            error;
        nomatch ->
            case gen_tcp:recv(Socket, 0, 5000) of
                {ok, Data} -> read_request(Socket, <<Acc/binary, Data/binary>>);
                {error, _} -> error
            end;
        _ ->
            {ok, Acc}
    end.

%% A comment line every 15 seconds keeps proxies from closing the stream
%% and notices pages that went away.
event_loop(Socket) ->
    Message = receive
        reload -> <<"event: reload\ndata: reload\n\n">>
    after 15000 ->
        <<": ping\n\n">>
    end,
    case gen_tcp:send(Socket, Message) of
        ok -> event_loop(Socket);
        {error, _} -> gen_tcp:close(Socket)
    end.

%% ---------------------------------------------------------------------------
%% SIGTERM: stop the app and the watchers instead of leaving them running
%% ---------------------------------------------------------------------------

trap_sigterm(Main) ->
    try
        os:set_signal(sigterm, handle),
        gen_event:swap_handler(erl_signal_server,
                               {erl_signal_handler, []},
                               {?MODULE, Main})
    catch
        _:_ -> ok
    end.

%% gen_event:swap_handler/3 passes {Args, TerminateResult}.
init({Main, _}) when is_pid(Main) -> {ok, Main};
init(Main) when is_pid(Main) -> {ok, Main}.

handle_event(sigterm, Main) ->
    Main ! sigterm,
    {ok, Main};
handle_event(_Signal, Main) ->
    {ok, Main}.

handle_call(_Request, Main) -> {ok, ok, Main}.
handle_info(_Info, Main) -> {ok, Main}.
terminate(_Reason, _Main) -> ok.
code_change(_OldVsn, Main, _Extra) -> {ok, Main}.
