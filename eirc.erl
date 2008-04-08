%%%-------------------------------------------------------------------
%%% File    : eirc.erl
%%% Author  : Peter Kristensen <>
%%% Description : irc bot
%%%
%%% Created : 21 Mar 2008 by Peter Kristensen <>
%%%-------------------------------------------------------------------
-module(eirc).

-behaviour(gen_server).

%% API
-export([start/0, 
	 stop/0, 
	 connect/2,
	 send/1,
	 disconnect/1,
	 say/2,
	 send_command/2,
	 set_nick/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-record(state, {socket,nick}).
-record(line, {prefix, command, params}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:call(?MODULE, stop).

send(Text) ->
    gen_server:call(?MODULE, {send, Text ++ "\r\n"}).

cast_send(Text) ->
    gen_server:cast(?MODULE, {send, Text ++ "\r\n"}).

set_nick(NewNick) ->
    gen_server:cast(?MODULE, {set_nick, NewNick}).

connect(Host, Port) ->
    gen_server:call(?MODULE, {connect, Host, Port}).
%    send("NICK erlbot"),
%    send("USER eb . . : ").

disconnect(Reason) ->
    gen_server:call(?MODULE ,{disconnect, Reason}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
    {ok, #state{nick="erlbot"}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------

handle_call({connect, Host, Port}, _From, State) ->
    {ok, Sock} = gen_tcp:connect(Host, Port, [list,{packet,line}]),
    cast_send(format_command("NICK",[State#state.nick])),
    cast_send(format_command("USER",[State#state.nick,".",".","Erlang bot"])),
    {reply, ok, State#state{socket=Sock}};

handle_call(stop, _From, State) ->
    gen_tcp:close(State#state.socket),
    {stop, normal, stopped, State};

handle_call({send, Text}, _From, State) ->
    gen_tcp:send(State#state.socket, Text),
    {reply, ok, State};

handle_call({disconnect, Reason}, _From, State) ->
    gen_tcp:send(State#state.socket, format_command("QUIT",[Reason]) ++ "\r\n"),
    {reply, ok, State};
handle_call({set_nick, NewNick}, _From, State) ->
    gen_tcp:send(State#state.socket, format_command("NICK",[NewNick]) ++ "\r\n"),
    {reply, ok, State#state{nick=NewNick}};

handle_call(_Request, _From, State) ->
    Reply = noreply,
    {reply, Reply, State}.


%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast({send, Text}, State) ->
    gen_tcp:send(State#state.socket, Text),
    {noreply,  State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------

handle_info({tcp, _Socket, Text}, State) ->
    Line = parse_line(Text),
    State1 = handle_command(Line,State),
    {noreply, State1};

handle_info(Info, State) ->
    io:format("unhandled info ~p~n",[Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

parse_line(Line) ->
    {Line1, LastParam} = 
	case string:str(Line, " :") of
	    0 ->
		{Line, []};
	    Index ->
		{string:substr(Line, 1, Index - 1),
		 [string:substr(Line, Index + 2) -- "\r\n"]}
	end,
    Tokens = string:tokens(Line1, " \r\n"),
    {Prefix, Tokens1} =
	case Line1 of
	    [$: | _] ->
		[$:|PFix] = hd(Tokens),
		{PFix, tl(Tokens)};
	    _ ->
		{none, Tokens}
	end,
    [Command | Params] = Tokens1,
    UCCommand = string:to_upper(Command),
    #line{prefix = Prefix, command = UCCommand, params = Params ++ LastParam}.

%%
% handle_command(#line, State) -> State
% 

handle_command(#line{command = "PING", params = [Reply]},State) ->
    send_command("PONG",[Reply]),
    State;

handle_command(#line{command = "PRIVMSG", params = [Place, Message], prefix = Who},State) ->
    Nic = State#state.nick,
    case {Place,string:str(Message,Nic)} of 
	{[$#|_Ch],0} -> State;
	{[$#|_Ch],_Idx} -> handle_channel_msg(Place, Message, Who,State);
	{Nic,_} -> handle_priv_msg(Message, Who,State);
	{_,_} -> State
    end;


handle_command(Line,State) ->
    io:format("Unhandled command: ~p~n",[Line]),
    State.

% sending:

say(Where, Message) ->
    cast_send(format_command("PRIVMSG",[Where, Message])).

send_command(Command, Params) ->
    cast_send(format_command(Command, Params)).
%    ParamString = make_param_string(Params),
%    cast_send(Command ++ ParamString).
%    io:format("Sending: ~s~n",[Command ++ ParamString]).

format_command(Command, Params) ->
    Command ++ make_param_string(Params).

make_param_string([]) -> "";
make_param_string([Last]) -> 
    case lists:member($\ ,Last) of 
	true -> " :" ++ Last;
	false -> " " ++ Last
    end;

make_param_string([P|Rest]) -> " " ++ P ++ make_param_string(Rest).
    
get_nick(Prefix) ->
    [Nick|_Rest] = string:tokens(Prefix, "!@"),
    Nick.

% Message handling:

handle_channel_msg(Channel, Message, Who, State) ->
    Nick = get_nick(Who),
    io:format("~s said: \"~s\" in ~s~n",[Nick, Message, Channel]),
    send_command("PRIVMSG",[Channel, "Hello " ++ Nick]),
    State.

handle_priv_msg(Message, Who, State) ->
    Nick = get_nick(Who),
    io:format("~s wrote \"~s\" to me~n",[Nick, Message]),
    send_command("PRIVMSG",[Nick,"Hey.."]),
    State.
