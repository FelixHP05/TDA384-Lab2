
-module(test).
-export([start/0, request/1]).


start() ->
    ServerPID = spawn(?MODULE, loop, [
        testServer,
        {},
        fun(_) -> ok end
    ]),
    request(ServerPID).

loop(ServerAtom, State, Handler) ->
    receive
        { Client, ServerAtom, request, Request} ->
            Client ! {self(), ServerAtom, response, Handler(Request)},
            loop(ServerAtom, State, Handler)
        _ -> 
            loop(ServerAtom, State, Handler)
    end.

request(ServerPID) -> 
    
    ServerPID ! {self(), testServer, request, {}},
    receive
        {ServerPID, testServer, response, Response} -> Response
    end.


