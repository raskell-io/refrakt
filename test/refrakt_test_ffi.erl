-module(refrakt_test_ffi).
-export([set_cwd/1, current_directory/0]).

set_cwd(Path) ->
    case file:set_cwd(binary_to_list(Path)) of
        ok -> {ok, nil};
        {error, _Reason} -> {error, nil}
    end.

current_directory() ->
    case file:get_cwd() of
        {ok, Dir} -> {ok, list_to_binary(Dir)};
        {error, _Reason} -> {error, nil}
    end.
