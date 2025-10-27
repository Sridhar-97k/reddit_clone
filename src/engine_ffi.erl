-module(engine_ffi).
-export([write_file/2]).

%% Wrapper around file:write_file that converts Erlang result to boolean
write_file(Filename, Content) ->
    case file:write_file(Filename, Content) of
        ok -> true;
        {error, _Reason} -> false
    end.