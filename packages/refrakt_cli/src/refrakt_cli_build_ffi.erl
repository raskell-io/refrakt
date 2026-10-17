-module(refrakt_cli_build_ffi).
-export([run_cmd/1]).

%% os:cmd/1 decodes UTF-8 output into a list of code points, which
%% list_to_binary/1 rejects as soon as the output contains anything outside
%% Latin-1 (e.g. the box-drawing characters in Gleam compiler warnings).
run_cmd(Cmd) ->
    Result = os:cmd(unicode:characters_to_list(Cmd)),
    unicode:characters_to_binary(Result).
