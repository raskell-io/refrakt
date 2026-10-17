-module(refrakt_dev_error_ffi).
-export([format_stacktrace/1]).

format_stacktrace(_Exception) ->
    %% Gleam's exception.rescue does not expose the original stacktrace,
    %% so report the current process stacktrace instead.
    Trace = case erlang:process_info(self(), current_stacktrace) of
        {current_stacktrace, ST} -> ST;
        _ -> []
    end,
    format_frames(Trace, []).

format_frames([], Acc) ->
    list_to_binary(lists:reverse(Acc));
format_frames([{Module, Function, Arity, Info} | Rest], Acc) ->
    File = proplists:get_value(file, Info, "unknown"),
    Line = proplists:get_value(line, Info, 0),
    ArityStr = if
        is_integer(Arity) -> integer_to_list(Arity);
        is_list(Arity) -> integer_to_list(length(Arity));
        true -> "?"
    end,
    Frame = io_lib:format("  ~s.~s/~s~n    ~s:~p~n", [
        Module, Function, ArityStr, File, Line
    ]),
    format_frames(Rest, [iolist_to_binary(Frame) | Acc]);
format_frames([_ | Rest], Acc) ->
    format_frames(Rest, Acc).
