-module(refrakt_format_ffi).
-export([format_files/1]).

format_files(Paths) ->
    GleamFiles = [binary_to_list(P) || P <- Paths, filename:extension(binary_to_list(P)) =:= ".gleam"],
    case GleamFiles of
        [] -> nil;
        _ ->
            Cmd = "gleam format " ++ string:join(GleamFiles, " "),
            os:cmd(Cmd),
            nil
    end.
