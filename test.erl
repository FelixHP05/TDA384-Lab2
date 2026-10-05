
-module(test).
-export([start/0, request/1]).


start() ->
    ServerPID = spawn(?MODULE, loop, [
        testServer,
        {},
        fun(_) -> ok end
    ]),
    request(ServerPID).



chatServerHandler(State, {}) ->


request(ServerPID) -> 
    
    ServerPID ! {self(), testServer, request, {}},
    receive
        {ServerPID, testServer, response, Response} -> Response
    end.


