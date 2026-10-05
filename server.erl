-module(server).
-export([start/1,stop/1]).
-record(serverState, {
    messages,     % map Channel => {Sender, Content}[]
    subscribers   % map Channel => ClientPID[]
}).



% Start a new *registered* server process with the given name
% Takes ServerAtom, returns PID
start(ServerAtom) ->
    genserver:start(
        ServerAtom,
        #serverState{ messages = maps:new(), subscribers = maps:new() },
        fun handler/2
    ).
% Stop the server process registered to the given name,
% together with any other associated processes
stop(ServerAtom) ->
    % TODO Implement function
    % Return ok
    not_implemented.


% Handles Clients' requests
% Takes
%     State - current `serverState` record
%     Request - tuple sent from client
% Returns tuple of
%     reply 
%     Reply - tuple or atom sent to client
%     NewState - new `serverState` record
handler(State, {message_send, Channel, Sender, Content}) ->

    Messages = maps:get(Channel, State#serverState.messages),
    NewMessages = [ {Sender, Content} | Messages ],
    NewState = State#serverState{ messages = NewMessages },
    
    lists:foreach(
        fun()    
        ),
    NewState.


