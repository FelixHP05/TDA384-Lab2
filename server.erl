-module(server).
-export([start/1,stop/1]).
-record(serverState, {
    messages = maps:new(),     % map Channel => {Sender, Content}[]
    subscribers = maps:new(),   % map Channel => ClientPID[]
    nicks = maps:new()
}).



% Start a new *registered* server process with the given name
% Takes ServerAtom, returns PID
start(ServerAtom) ->
    genserver:start(
        ServerAtom,
        #serverState{ 
            messages = maps:new(), 
            subscribers = maps:new(),
            nicks = maps:new()
        },
        fun handler/2
    ).
% Stop the server process registered to the given name,
% together with any other associated processes
stop(ServerAtom) ->
    genserver:stop(ServerAtom).


% Handles Clients' requests
% Takes
%     State - current `serverState` record
%     Request - tuple sent from client
% Returns tuple of
%     reply 
%     Reply - tuple or atom sent to client
%     NewState - new `serverState` record


handler(State, {message_send, Channel, Sender, Content}) ->

    % prepend to list
    Messages = maps:get(Channel, State#serverState.messages, []),
    NewMessages = [ {Sender, Content} | Messages ],
    NewState = State#serverState{ messages = NewMessages },
    
    % notify subscribers
    lists:foreach(
            fun (SubscriberPID) -> 
                SubscriberPID ! { messsage_receive, Channel, Sender, Content}, %%% don't know how to send to client????
                receive ok -> ok end
            end,
            maps:get(Channel, State#serverState.subscribers)
        ),
    NewState;

handler(State, {subscribe, Channel, SubscriberPID}) ->

    Subscribers = maps:get(Channel, State#serverState.subscribers, []),
    NewSubscribers = [ SubscriberPID | Subscribers ],
    NewState = State#serverState{ subscribers = NewSubscribers },
    NewState;

handler(State, {unsubscribe, Channel, SubscriberPID}) ->

    Subscribers = maps:get(Channel, State#serverState.subscribers, []),
    NewSubscribers = lists:delete(SubscriberPID, Subscribers),
    NewState = State#serverState{ subscribers = NewSubscribers },
    NewState.
