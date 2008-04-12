%%%-------------------------------------------------------------------
%%% File    : eirc_sup.erl
%%% Author  : Peter Kristensen <>
%%% Description : eirc supervisor
%%%
%%% Created : 12 Apr 2008 by Peter Kristensen <>
%%%-------------------------------------------------------------------
-module(eirc_sup).

-behaviour(supervisor).

%% API
-export([start_link/0,
	start_in_shell_for_testing/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the supervisor
%%--------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_in_shell_for_testing() ->
    {ok, Pid} = supervisor:start_link({local, ?SERVER}, ?MODULE, []),
    unlink(Pid).

%%====================================================================
%% Supervisor callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% Func: init(Args) -> {ok,  {SupFlags,  [ChildSpec]}} |
%%                     ignore                          |
%%                     {error, Reason}
%% Description: Whenever a supervisor is started using 
%% supervisor:start_link/[2,3], this function is called by the new process 
%% to find out about restart strategy, maximum restart frequency and child 
%% specifications.
%%--------------------------------------------------------------------
init([]) ->
    {ok, {{one_for_one, 3, 10},
	  [{tag1,
	    {eirc, start, []},
	    permanent,
	    10000,
	    worker,
	    [eirc]}]}}.

%%====================================================================
%% Internal functions
%%====================================================================
