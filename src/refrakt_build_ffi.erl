-module(refrakt_build_ffi).
-export([run_cmd/1]).

run_cmd(Cmd) ->
    Result = os:cmd(binary_to_list(Cmd)),
    list_to_binary(Result).
