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
-export([start/0, stop/0, connect/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-record(state, {socket}).

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

connect(Host, Port) ->
    gen_server:call(?MODULE, {connect, Host, Port}),
    send("NICK erlbot"),
    send("USER eb . . : ").


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
    {ok, #state{}}.

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
    {ok, Sock} = gen_tcp:connect(Host, Port, []),
    {reply, ok, State#state{socket=Sock}};

handle_call(stop, _From, State) ->
    gen_tcp:close(State#state.socket),
    {stop, normal, stopped, State};

handle_call({send, Text}, _From, State) ->
    gen_tcp:send(State#state.socket, Text),
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    Reply = noreply,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------

handle_info({tcp, Socket, Text}, State) ->
    io:format("TEXT:: ~s~n",[Text]),
    {noreply, State};

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
