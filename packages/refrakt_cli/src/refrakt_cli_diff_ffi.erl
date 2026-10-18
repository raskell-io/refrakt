-module(refrakt_cli_diff_ffi).
-export([make_temp_dir/0, run_in/2, unified_diff/4, halt/1]).

%% A fresh, empty directory under $TMPDIR (or /tmp).
make_temp_dir() ->
    Base = case os:getenv("TMPDIR") of
        false -> "/tmp";
        "" -> "/tmp";
        Dir -> Dir
    end,
    Name = io_lib:format("refrakt-diff-~s-~b",
                         [os:getpid(), erlang:unique_integer([positive])]),
    Path = filename:join(Base, lists:flatten(Name)),
    case file:make_dir(Path) of
        ok -> {ok, unicode:characters_to_binary(Path)};
        {error, _} -> {error, nil}
    end.

%% Run Fun with the working directory set to Dir and its printed output
%% captured instead of shown. Restores both afterwards. Returns
%% {ok, Output}, or {error, Output} when Fun crashed (Output then ends with
%% the crash reason).
run_in(Dir, Fun) ->
    {ok, OldCwd} = file:get_cwd(),
    OldLeader = group_leader(),
    Sink = spawn(fun() -> sink([]) end),
    case file:set_cwd(unicode:characters_to_list(Dir)) of
        ok ->
            group_leader(Sink, self()),
            Result = try
                Fun(),
                ok
            catch
                Class:Reason ->
                    {crashed, io_lib:format("~p: ~p", [Class, Reason])}
            after
                group_leader(OldLeader, self()),
                ok = file:set_cwd(OldCwd)
            end,
            Output = collect(Sink),
            case Result of
                ok -> {ok, Output};
                {crashed, Why} ->
                    {error, unicode:characters_to_binary([Output, Why])}
            end;
        {error, Reason} ->
            exit(Sink, kill),
            {error, unicode:characters_to_binary(
                io_lib:format("cannot enter ~ts: ~p", [Dir, Reason]))}
    end.

sink(Acc) ->
    receive
        {io_request, From, ReplyAs, Request} ->
            {Reply, Acc1} = io_request(Request, Acc),
            From ! {io_reply, ReplyAs, Reply},
            sink(Acc1);
        {collect, From} ->
            From ! {collected, self(), lists:reverse(Acc)};
        _ ->
            sink(Acc)
    end.

io_request({put_chars, Encoding, Chars}, Acc) ->
    {ok, [unicode:characters_to_binary(Chars, Encoding) | Acc]};
io_request({put_chars, Encoding, M, F, A}, Acc) ->
    io_request({put_chars, Encoding, apply(M, F, A)}, Acc);
io_request({put_chars, Chars}, Acc) ->
    io_request({put_chars, latin1, Chars}, Acc);
io_request({requests, Requests}, Acc) ->
    lists:foldl(fun(R, {_, A}) -> io_request(R, A) end, {ok, Acc}, Requests);
io_request({get_geometry, _}, Acc) ->
    {{error, enotsup}, Acc};
io_request({setopts, _}, Acc) ->
    {ok, Acc};
io_request(getopts, Acc) ->
    {[], Acc};
io_request(_, Acc) ->
    {eof, Acc}.

collect(Sink) ->
    Sink ! {collect, self()},
    receive
        {collected, Sink, Output} -> unicode:characters_to_binary(Output)
    after 5000 ->
        <<>>
    end.

%% `diff -u` of two files, labelled LabelA and LabelB. {error, nil} when
%% there is no diff executable.
unified_diff(FileA, FileB, LabelA, LabelB) ->
    case os:find_executable("diff") of
        false -> {error, nil};
        Diff ->
            Args = ["-u", "--label", LabelA, "--label", LabelB, FileA, FileB],
            Port = open_port({spawn_executable, Diff},
                             [{args, [unicode:characters_to_list(A) || A <- Args]},
                              exit_status, binary, use_stdio, stderr_to_stdout]),
            collect_port(Port, [])
    end.

collect_port(Port, Acc) ->
    receive
        {Port, {data, Data}} -> collect_port(Port, [Data | Acc]);
        {Port, {exit_status, Status}} when Status =< 1 ->
            {ok, iolist_to_binary(lists:reverse(Acc))};
        {Port, {exit_status, _}} ->
            {error, nil}
    end.

halt(Status) ->
    erlang:halt(Status).
