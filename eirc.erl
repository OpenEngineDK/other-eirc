%%%-------------------------------------------------------------------
%%% File    : eirc.erl
%%% Author  : Peter Kristensen <>
%%% Description : irc bot
%%%
%%% Created : 21 Mar 2008 by Peter Kristensen <>
%%%-------------------------------------------------------------------
-module(eirc).

-behaviour(gen_server).

% debugging
-compile(export_all).

%% API
-export([start/0,
	 start_link/1, 
	 stop/0, 
	 connect/1,
	 connect/2,
	 send/1,
	 disconnect/1,
	 join/1,
	 say/2,
	 send_command/2,
	 set_nick/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("ircnum.hrl").

-record(user, {nick,
	       last_seen=never, 
	       last_spoke=never,
	       last_message="", 
	       online=false,
	       bytes_used=0,
	       spoken_lines=0}).
-record(state, {socket,nick,users=[]}).
-record(line, {prefix, command, params}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start() ->
    start_link(["irc.freenode.org",
	       6667,
	       "#openengine",
	       "erlbot"]).


start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

stop() ->
    gen_server:call(?MODULE, stop).

join(Channel) ->
    cast_send(format_command("JOIN",[Channel])).
say(Where, Message) ->
    cast_send(format_command("PRIVMSG",[Where, Message])).

send(Text) ->
    gen_server:call(?MODULE, {send, Text ++ "\r\n"}).

cast_send(Text) ->
    gen_server:cast(?MODULE, {send, Text ++ "\r\n"}).

set_nick(NewNick) ->
    gen_server:cast(?MODULE, {set_nick, NewNick}).

connect(Host) -> 
    connect(Host, 6667). % default port

get_state() ->
    gen_server:call(?MODULE, {get_state}).

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
init([Host, Port, Channel, NickservPassword]) ->
    Nick = "erlbot",
    {ok,Sock} = gen_tcp:connect(Host, Port, [list,{packet,line}]),
    gen_tcp:send(Sock, format_command("NICK",[Nick]) ++ "\r\n"),
    gen_tcp:send(Sock, format_command("USER",[Nick,".",".","Erlang bot"]) ++ "\r\n"),
    gen_tcp:send(Sock, format_command("JOIN",[Channel]) ++ "\r\n"),
    gen_tcp:send(Sock, format_command("PRIVMSG",["nickserv","identify " ++ NickservPassword]) ++ "\r\n"),
  
    {ok, #state{nick=Nick,socket=Sock}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------

%% handle_call({connect, Host, Port}, _From, State) ->
%%     {ok, Sock} = gen_tcp:connect(Host, Port, [list,{packet,line}]),
%%     cast_send(format_command("NICK",[State#state.nick])),
%%     cast_send(format_command("USER",[State#state.nick,".",".","Erlang bot"])),
%%     {reply, ok, State#state{socket=Sock}};

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
handle_call({get_state}, _From, State) ->
    {reply, State, State};

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
    io:format("Receiving: ~p~n",[Text]),
    State1 = handle_command(Line,State),
    %io:format("~p~n",[State1]),
    {noreply, State1};

handle_info({tcp_closed,_Port}, State) ->
    {stop, "tcp closed", State};

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
    io:format("New Code~n"),
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
    case Place of 
	[$#|_Ch] -> read_channel_msg(Place, Message, Who, State);
	_ -> read_priv_msg(Message, Who, State)
    end;

handle_command(#line{command = ?RPL_NAMREPLY, params = [_Me,_ChType,_Channel,NickNames]}, State) ->
    Users = lists:map(fun (X) -> #user{nick=string:to_lower(X),
				       last_seen=calendar:local_time(),
				       online=true}
			      end, 
		      string:tokens(NickNames," ")),
%%     SortedUsers = lists:keysort(2,Users),
%%     io:format("Merging: ~p ~n ~p~n",[SortedUsers,State#state.users]),
%%     MergedUsers = lists:keymerge(2, SortedUsers, State#state.users),
%%     io:format("Got some users: ~p~n",[MergedUsers]),
    NewUsers = lists:foldl(fun update_user/2, State#state.users, Users),
    io:format("New Users: ~p~n",[NewUsers]),
    State#state{users=NewUsers};

handle_command(#line{prefix=Who, command = "JOIN", params = [_Channel]}, State) ->
    Nick = get_nick(Who),
    NewUser =  case get_user(State#state.users, Nick) of 
 		   User = #user{} -> User#user{last_seen=calendar:local_time(), online=true};
 		   false -> #user{nick=Nick,last_seen=calendar:local_time(), online=true}
		end,

    NewUsers = update_user(NewUser, State#state.users),
    State#state{users=NewUsers};

handle_command(#line{prefix=Who, command = "PART", params = [_Channel,_Why]}, State) ->
    Nick = get_nick(Who),
    NewUser =  case get_user(State#state.users, Nick) of 
 		   User = #user{} -> User#user{last_seen=calendar:local_time(), online=false};
 		   false -> #user{nick=Nick,last_seen=calendar:local_time(), online=false}
		end,

    NewUsers = update_user(NewUser, State#state.users),
    State#state{users=NewUsers};

handle_command(#line{prefix=Who, command = "QUIT", params = [_Why]}, State) ->
    Nick = get_nick(Who),
    NewUser =  case get_user(State#state.users, Nick) of 
 		   User = #user{} -> User#user{last_seen=calendar:local_time(), online=false};
 		   false -> #user{nick=Nick,last_seen=calendar:local_time(), online=false}
		end,

    NewUsers = update_user(NewUser, State#state.users),
    State#state{users=NewUsers};

handle_command(#line{prefix=Who, command = "NICK", params = [NewNick]}, State) ->
    Nick = get_nick(Who),
    NewUser =  case get_user(State#state.users, Nick) of 
 		   User = #user{} -> User#user{nick=NewNick,last_seen=calendar:local_time(), online=true};
 		   false -> #user{nick=NewNick,last_seen=calendar:local_time(), online=true}
	       end,
    
    NewUsers = modify_user(fun (X) -> X#user{nick=NewNick}
			   end,
			   NewUser, 
			   
			   State#state.users),
    
    State#state{users=NewUsers};


handle_command(Line,State) ->
    io:format("UnhandledCommand: ~p~n",[Line]),
    State.

modify_user(Fun, User, State = #state{}) ->
%%     io:format("U: ~p~n",[User]),
%%     io:format("old users ~p~n",[State#state.users]),
    Users = modify_user(Fun, User, State#state.users),
%    io:format("new users ~p~n",[Users]),
    State#state{users = Users};

modify_user(Fun, User, []) ->
    [Fun(User)];
modify_user(Fun, _User = #user{nick=Nick}, [Last = #user{nick=Nick}]) ->
    [Fun(Last)];
modify_user(Fun, User, [Last]) ->
    [Fun(User),Last];
modify_user(Fun, _User = #user{nick=Nick}, [Head = #user{nick=Nick}|Tail]) ->
    [Fun(Head)|Tail];
modify_user(Fun, User, [Head|Tail]) ->
    [Head|modify_user(Fun,User,Tail)].


update_user(User, []) ->
    [User];
update_user(User = #user{nick=Nick}, [Last = #user{nick=Nick}]) ->
    [merge_user(Last,User)];
update_user(User, [Last]) ->
    [User,Last];
update_user(User = #user{nick=Nick}, [Head = #user{nick=Nick}|Tail]) ->
    [merge_user(Head,User)|Tail];
update_user(User, [Head|Tail]) ->
    [Head|update_user(User,Tail)].

merge_user(_Old, New) ->
    New.

get_user(Users, Nick) ->
    case lists:keysearch(Nick, 2, Users) of
	{value, User} -> User;
	false -> false
    end.
	     

% sending:


send_command(Command, Params) ->
    io:format("Sending: ~s~n",[format_command(Command,Params)]),
    cast_send(format_command(Command, Params)).
%    ParamString = make_param_string(Params),
%    cast_send(Command ++ ParamString).


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
    string:to_lower(Nick).

get_term(String) ->
    case erl_scan:string(String) of
	{ok, Tokens, _} -> case erl_parse:parse_term(Tokens) of 
			       {ok, Term} -> {ok, Term};
			       {error, _Err} -> scan_lazy_term(String)
			   end;
	_ -> {error, scan_fail}
    end.
	    
%% scan_lazy_term(String) ->
%%     Tokens = string:tokens(String," "),
%%     %[H|T] = Tokens,
%%     %AtomedList = [list_to_atom(H)|T],
%%     Atoms = lists:map(fun erlang:list_to_atom/1, Tokens),
%%     {ok,list_to_tuple(Atoms)}.

scan_lazy_term(String) ->
    {ok, Tokens, _} = erl_scan:string(String),
    io:format("~p~n",[Tokens]),
    Up = unpack_tokens(Tokens),
    io:format("~p~n",[Up]),
    {ok,list_to_tuple(Up)}.

unpack_tokens([]) ->
    [];
%% unpack_tokens([{'{',_}|T]) ->
%%     [{unpack_tokens(T)]
unpack_tokens([H|T]) ->
    [unpack_token(H)|unpack_tokens(T)].

unpack_token({atom, _, Atm}) ->
    Atm;
unpack_token({var,_,Var}) ->
    Var;
unpack_token({string, _, Str}) ->
    Str;


unpack_token(_) ->
    err.

% Message handling:

trim("", _, _) -> "";						
trim(Str, right, Chars) ->
    lists:reverse(trim(lists:reverse(Str), left, Chars));
trim([C|Str], left, Chars) ->
    case lists:member(C,Chars) of
	true  -> trim(Str,left,Chars);
	false -> [C|Str]
    end.

remove_prefix(Message, Prefix) ->
    case string:str(Message, Prefix) of 
	1 -> PrePrefix = string:substr(Message, string:len(Prefix)+1),
	     trim(PrePrefix, left, ",.: ");
	     %lists:foldl(fun(X,Msg) -> string:strip(Msg, left, X) end, PrePrefix, ",.: ");
	_ -> Message
    end.
    

read_channel_msg(Channel, Message, Who, State) ->
    Nick = State#state.nick,
    MessageWithoutPrefix = remove_prefix(Message, Nick),

    case string:strip(MessageWithoutPrefix) of 
	[$!|Msg] -> handle_channel_msg(Channel, Msg, Who, State);
	_ -> modify_user(fun (User) -> User#user{last_message=Message,
						 last_spoke=calendar:local_time(),
						 bytes_used=(User#user.bytes_used + length(Message)),
						 spoken_lines=User#user.spoken_lines + 1}
				 end,
			 #user{nick=get_nick(Who)},
			 State)
    end.
					  

read_priv_msg(Message, Who, State) ->
    handle_priv_msg(Message, Who, State).

handle_channel_msg(Channel, Message, Who, State) ->
    Nick = get_nick(Who),
    io:format("~s said: \"~s\" in ~s~n",[Nick, Message, Channel]),
    {Reply,NewState} = case get_term(Message) of
			   {ok, Term} -> reply_to_term(Term, Who, Channel, State);
			   {error, _Why} -> {Nick ++ ", what?",State}
		       end,

    send_command("PRIVMSG",[Channel, Reply]),
    NewState.

handle_priv_msg(Message, Who, State) ->
    Nick = get_nick(Who),
    io:format("~s wrote \"~s\" to me~n",[Nick, Message]),
    {Reply,NewState} = case get_term(Message) of
			   {ok, Term} -> reply_to_term(Term, Who, privmsg, State);
			   {error, _Why} -> {"what?",State}
		       end,
    
    send_command("PRIVMSG",[Nick,Reply]),
    NewState.

% taking action..
reply_to_term({stats, known_users}, _From, _Where, State) ->
    {io_lib:format("~p users are known",[length(State#state.users)]), State};

reply_to_term({hello}, Who, _Where, State) ->
    {"Hello " ++ get_nick(Who), State};

reply_to_term({spoke, Who}, From, Where, State) when is_atom(Who) ->
    reply_to_term({spoke, atom_to_list(Who)}, From, Where, State);

reply_to_term({spoke, Who}, _From, _Where, State) when is_list(Who) ->
    Nick = string:to_lower(Who),
    User = lists:keysearch(Nick, 2, State#state.users),
        Reply = case User of
		    {value, _U = #user{last_spoke=never}} -> Nick ++" never said a thing!";
		    {value, U = #user{}} -> io_lib:format("The last thing ~s said was: \"~s\" at ~w~n",
							   [U#user.nick, U#user.last_message, U#user.last_spoke]);
		false -> "Never heard of " ++ Nick
	    end,
    {Reply,State};

reply_to_term({ustat, Who}, From, Where, State) when is_atom(Who) ->
    reply_to_term({ustat, atom_to_list(Who)}, From, Where, State);

reply_to_term({ustat, Who}, _From, _Where, State) when is_list(Who) ->
    Nick = string:to_lower(Who),
    User = lists:keysearch(Nick, 2, State#state.users),
        Reply = case User of
		    {value, _U = #user{last_spoke=never}} -> Nick ++" never said a thing!";
		    {value, U = #user{}} -> io_lib:format("~s have used ~w bytes for ~w lines",
							   [U#user.nick, 
							    U#user.bytes_used,
							    U#user.spoken_lines]);
		false -> "Never heard of " ++ Nick
	    end,
    {Reply,State};




reply_to_term({seen, Who}, From, Where, State) when is_atom(Who) ->
    reply_to_term({seen, atom_to_list(Who)}, From, Where, State);

reply_to_term({seen, Who}, From, _Where, State) when is_list(Who) ->
    Nick = string:to_lower(Who),
    User = lists:keysearch(Nick, 2, State#state.users),
    io:format("User: ~p~n",[User]),
    Reply = case {get_nick(From),User} of
		{Nic,{value, _U = #user{nick=Nic}}} -> Nick ++ ", can't see youself?";
		{_,{value, U = #user{online=false}}} -> io_lib:format("~s was last seen at: ~p",
							      [U#user.nick, U#user.last_seen]);
		{_,{value, U = #user{online=true}}} -> io_lib:format("~s is online right now!",[U#user.nick]);
		
		{_,false} -> "Never heard of " ++ Nick
	    end,
    {Reply,State};

reply_to_term({die}, Who, _Where, State) ->
    Reply = case is_admin(Who) of 
		true -> cast_send(format_command("QUIT",[get_nick(Who) ++" told me to die :( "])),
			"bye";
		false -> "You are not an admin!"
	    end,
    {Reply,State};

reply_to_term({tell, Who, What}, _Who, _Where, State) when is_list(Who), is_list(What) ->
    cast_send(format_command("PRIVMSG",[Who, What])),
    {"ok",State};

reply_to_term({echo, What}, _Who, _Where, State)  ->
    String = stringify(What), %lists:flatten(io_lib:format("~p",[What])),
    {String,State};

reply_to_term(_Term, Who, _Where, State) ->
    Nick = get_nick(Who),
    {Nick ++ ", you are not making sense!",State}.

%stringify

% problem! [a,b] is a list, but not at string... guard for strings?

%% stringify(Atom) when is_atom(Atom) ->
%%     atom_to_list(Atom);
%% stringify(List) when is_list(List) ->
%%     List;
stringify(Other) ->
    lists:flatten(io_lib:format("~p",[Other])).

% permissions

is_admin(Who) ->
    io:format("echoking admin ~s~n",[Who]),
    case get_nick(Who) of 
	"ptx" -> true;
	"zerny" -> true;
	_ -> false
    end.
	     
