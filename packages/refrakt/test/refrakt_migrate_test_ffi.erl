-module(refrakt_migrate_test_ffi).
-export([start_log/0, append_log/2, read_log/1]).

%% A log kept in the process dictionary: migrate:run calls its callbacks
%% from the calling process, so the test can read back what they received.
start_log() ->
    Log = make_ref(),
    put(Log, []),
    Log.

append_log(Log, Entry) ->
    put(Log, [Entry | get(Log)]),
    nil.

read_log(Log) ->
    lists:reverse(get(Log)).
