-module(client).
-export([handle/2, initial_state/3]).

% This record defines the structure of the state of a client.
% Add whatever other fields you need.
-record(client_st, {
    gui, % atom of the GUI process
    nick, % nick/username of the client
    server, % atom of the chat server
% keep a local map of channels we join ChannelName => ChannelPID
% allows to talk directly to the channel processes later
    channels = maps:new() 
}).

% Return an initial state record. This is called from GUI.
% Do not change the signature of this function.
initial_state(Nick, GUIAtom, ServerAtom) ->
    #client_st{
        gui = GUIAtom,
        nick = Nick,
        server = ServerAtom,
        channels = maps:new()
    }.


% Join channel
handle(St, {join, Channel}) ->
    % TODO: Implement this function
    % {reply, ok, St} ;
    % check if we are already in this channel locally
    case maps:is_key(Channel, St#client_st.channels) of
        true ->
            {reply, {error, user_already_joined, "USER IS HEREE!"}, St};
        false ->
            % ask main server for channel's PID
            % we also send our current nick here so the server knows it (for the distinction task).
            try genserver:request(St#client_st.server, {join, Channel, self(), St#client_st.nick}) of
                {ok, ChannelPID} ->
                    %after getting PID, we subscribe directly to the channel process
                    try genserver:request(ChannelPID, {subscribe, self()}) of
                        ok ->
                            % save the channel PID in our local state so we can message it directly later
                            NewChannels = maps:put(Channel, ChannelPID, St#client_st.channels),
                            {reply, ok, St#client_st{channels = NewChannels}};
                        {error, Atom, Msg} ->
                            {reply, {error, Atom, Msg}, St}
                    catch
                        _:_ -> {reply, {error, server_not_reached, "Channel process is dead"}, St}
                    end;
                {error, Atom, Msg} ->
                    {reply, {error, Atom, Msg}, St}
            catch
                _:_ -> {reply, {error, server_not_reached, "Main server not reached"}, St}
            end
    end;

% Leave channel
handle(St, {leave, Channel}) ->
    case maps:find(Channel, St#client_st.channels) of
        {ok, ChannelPID} ->
            % unsubscribe by talking directly to the channel process
            try genserver:request(ChannelPID, {unsubscribe, self()}) of
                ok ->
                    NewChannels = maps:remove(Channel, St#client_st.channels),
                    {reply, ok, St#client_st{channels = NewChannels}};
                {error, Atom, Msg} ->
                    {reply, {error, Atom, Msg}, St}
            catch
                % if channel process crashed, we consider ourselves successfully removed from it
                _:_ ->
                    NewChannels = maps:remove(Channel, St#client_st.channels),
                    {reply, ok, St#client_st{channels = NewChannels}}
            end;
        error ->
            % if we dont have the channel locally, just check if the main server is still alive
            % to give the correct error message for the tests
            case whereis(St#client_st.server) of
                undefined -> {reply, {error, server_not_reached, "Main server is down"}, St};
                _ -> {reply, {error, user_not_joined, "USER NOT HEREE!"}, St}
            end
    end;

% Sending message (from GUI, to channel)
handle(St, {message_send, Channel, Msg}) ->
    % TODO: Implement this function
    % {reply, ok, St} ;
    case maps:find(Channel, St#client_st.channels) of
        {ok, ChannelPID} ->
            % concurrency! send the message directly to the channel PID, bypassing the main server
            try genserver:request(ChannelPID, {message_send, St#client_st.nick, Msg, self()}) of
                ok -> {reply, ok, St};
                {error, Atom, MsgErr} -> {reply, {error, Atom, MsgErr}, St}
            catch
                _:_ -> {reply, {error, server_not_reached, "Server not reached"}, St}
            end;
        error ->
            % we not in the channel. we double check with the main server if the channel exists
            % this handles the test case "write_not_joined3"
            try genserver:request(St#client_st.server, {check_channel, Channel}) of
                true -> {reply, {error, user_not_joined, "USER NOT HERE"}, St};
                false -> {reply, {error, server_not_reached, "Channel not exist"}, St}
            catch
                _:_ -> {reply, {error, server_not_reached, "Main server not reached"}, St}
            end
    end;

% This case is only relevant for the distinction assignment!
% Change nick (no check, local only)
handle(St, {nick, NewNick}) ->
    try genserver:request(St#client_st.server, {nick, self(), NewNick}) of
        ok -> {reply, ok, St#client_st{nick = NewNick}};
        {error, Atom, Msg} -> {reply, {error, Atom, Msg}, St}
    catch
        _:_ -> {reply, {error, server_not_reached, "Server not reached"}, St}
    end;

% ---------------------------------------------------------------------------
% The cases below do not need to be changed...
% But you should understand how they work!

% Get current nick
handle(St, whoami) ->
    {reply, St#client_st.nick, St} ;

% Incoming message (from channel, to GUI)
handle(St = #client_st{gui = GUI}, {message_receive, Channel, Nick, Msg}) ->
    gen_server:call(GUI, {message_receive, Channel, Nick++"> "++Msg}),
    {reply, ok, St} ;

% Quit client via GUI
handle(St, quit) ->
    % Any cleanup should happen here, but this is optional
    {reply, ok, St} ;

% Catch-all for any unhandled requests
handle(St, Data) ->
    {reply, {error, not_implemented, "Client does not handle this command"}, St}.
