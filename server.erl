-module(server).
-export([start/1,stop/1]).

%state for main server. keeps track of the channels and unique nicknames
-record(serverState, {
    channels = maps:new(),     % Channel name => ChannelPID
    nicks = maps:new() %ClientPID => Nick
}).

%state for each individual channel process
-record(channelState, {
    name,
    subscribers = []       % List of ClientPIDs in channel
}).

% Start a new *registered* server process with the given name
% Takes ServerAtom, returns PID
start(ServerAtom) ->
    genserver:start(
        ServerAtom,
        #serverState{},
        fun handler/2
    ).

stop(ServerAtom) ->
    % before killing the main server, we clean up and stop all the channel processes we spawned
    try genserver:request(ServerAtom, stop_channels) catch _:_ -> ok end,
    genserver:stop(ServerAtom).


% helper to shut down all channels when main server stops
handler(State, stop_channels) ->
    maps:foreach(fun(_Name, PID) -> 
        try genserver:stop(PID) catch _:_ -> ok end 
    end, State#serverState.channels),
    {reply, ok, State};

%check if a channel exists (used by the client for error handling)
handler(State, {check_channel, Channel}) ->
    Exists = maps:is_key(Channel, State#serverState.channels),
    {reply, Exists, State};


% handle a user wanting to join a channel
handler(State, {join, Channel, ClientPID, Nick}) ->
    % we save the user's initial nick right away to prevent nick collisions from the start
    NewNicks = maps:put(ClientPID, Nick, State#serverState.nicks),
    StateWithNick = State#serverState{nicks = NewNicks},
    
    case maps:find(Channel, StateWithNick#serverState.channels) of
        {ok, ChannelPID} ->
            % channel already exists, just return its PID
            {reply, {ok, ChannelPID}, StateWithNick};
        error ->
            % channel doesn't exist yet, so we spawn a brand new separate process for it
            ChannelAtom = list_to_atom(Channel),
            ChannelPID = genserver:start(ChannelAtom, #channelState{name=Channel}, fun channel_handler/2),
            NewChannels = maps:put(Channel, ChannelPID, StateWithNick#serverState.channels),
            {reply, {ok, ChannelPID}, StateWithNick#serverState{channels = NewChannels}}
    end;


% handle changing nicknames
handler(State, {nick, ClientPID, NewNick}) ->
    ActiveNicks = maps:values(State#serverState.nicks),
    case lists:member(NewNick, ActiveNicks) of
        true ->
            %check if the nick is taken by this user or someone else
            case maps:get(ClientPID, State#serverState.nicks, undefined) of
                NewNick -> {reply, ok, State};
                _ -> {reply, {error, nick_taken, "Nickname is already taken"}, State}
            end;
        false ->
            % nick is free, update the map
            UpdatedNicksMap = maps:put(ClientPID, NewNick, State#serverState.nicks),
            {reply, ok, State#serverState{nicks = UpdatedNicksMap}}
    end;

handler(State, _Request) ->
    {reply, {error, not_implemented, "Server command not implemented"}, State}.


%channel process logic
% runs completely independent of the main server. each channel has its own loop.

channel_handler(State, {subscribe, SubscriberPID}) ->
    case lists:member(SubscriberPID, State#channelState.subscribers) of
        true ->
            {reply, {error, user_already_joined, "USER IS HEREE"}, State};
        false ->
            NewSubs = [SubscriberPID | State#channelState.subscribers],
            {reply, ok, State#channelState{subscribers = NewSubs}}
    end;

channel_handler(State, {unsubscribe, SubscriberPID}) ->
    case lists:member(SubscriberPID, State#channelState.subscribers) of
        false ->
            {reply, {error, user_not_joined, "USER NOT HEREE"}, State};
        true ->
            NewSubs = lists:delete(SubscriberPID, State#channelState.subscribers),
            {reply, ok, State#channelState{subscribers = NewSubs}}
    end;

channel_handler(State, {message_send, SenderNick, Msg, SenderPID}) ->
    case lists:member(SenderPID, State#channelState.subscribers) of
        false ->
            {reply, {error, user_not_joined, "USER NOT HEREE"}, State};
        true ->
            % find everyone except the person who sent the message
            Recipients = lists:delete(SenderPID, State#channelState.subscribers),
            Channel = State#channelState.name,
            %broadcast the message to all recipients
            lists:foreach(
                fun(SubPID) ->
                    %spawn a new process for each delivery so a slow/crashed client doesnt block the whole channel
                    spawn(fun() ->
                        try genserver:request(SubPID, {message_receive, Channel, SenderNick, Msg})
                        catch _:_ -> ok end
                    end)
                end,
                Recipients
            ),
            {reply, ok, State}
    end;

channel_handler(State, _Request) ->
    {reply, {error, not_implemented, "Channel command not implemented"}, State}.