-module(rnis_data_att_emul_load).

-behaviour(gen_server).

%% API
-export([start_link/0,
		 handle_reload/0,
		 get_atts/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-include("rnis_data_att_emul.hrl").

-record(state, {atts = [], timer_ref}).

%% ====================================================================
%% API functions
%% ====================================================================

start_link() ->
  gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

handle_reload()->
  gen_server:call(?MODULE, handle_reload).

get_atts()->
	gen_server:call(?MODULE, get_atts).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
	{ok, #state{}, 0}.

handle_call(handle_reload,_From,#state{atts = Atts,timer_ref = Ref}=State)->
	Atts = load_atts(),
	lager:info("Handel Reloaded Atts ~p", [length(Atts)]),
  	{reply, ok, State#state{atts = Atts}};
handle_call(get_atts,_From,#state{atts = Atts}=State)->
  	{reply, {ok,Atts}, State};
handle_call(_Request, _From, State) ->
  	{reply, ok, State}.

handle_cast(_Msg, State) ->
  	{noreply, State}.

handle_info(timeout, State) ->
	Atts = load_atts(),
	lager:info("Loaded Atts ~p", [length(Atts)]),
  	ReloadTimeout = application:get_env(rnis_data_att_emul,reload_atts_timeout, ?RELOAD_TIMEOUT),
  	{ok,Ref} = timer:send_after(ReloadTimeout, reload),
	{noreply, State#state{atts = Atts, timer_ref = Ref}};
handle_info(reload, #state{timer_ref = Ref}=State) ->
	timer:cancel(Ref),
	Atts = load_atts(),
	lager:info("Reloaded Atts ~p", [length(Atts)]),
	ReloadTimeout = application:get_env(rnis_data_att_emul,reload_atts_timeout, ?RELOAD_TIMEOUT),
	{ok,NewRef} = timer:send_after(ReloadTimeout, reload),
	{noreply, State#state{atts = Atts, timer_ref = NewRef}};
handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

load_atts()->
	LoadNode = application:get_env(rnis_data_att_emul,load_node, ?LOAD_NODE),
	Atts = rpc:call(LoadNode,mnesia,dirty_select,[att_descr,[{{att_descr,'_','$2','_','_','_'}, [], [['$2']]}]]), 
	[{Id,Name}||{Id,{Name,_}}<-[{Id,proplists:get_value(Prefix,?PREFIX)}||[{Prefix,Id}]<-Atts],Name=/=undefined].