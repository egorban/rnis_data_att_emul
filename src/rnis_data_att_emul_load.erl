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

-define(RELOAD_TIMEOUT, 60000).
-define(NODE, 'rnis@10.1.116.42').

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
	io:format("rnis_data_att_emul_load init~n"),
	{ok, #state{}, 0}.

handle_call(reload,_From,#state{atts = Atts,timer_ref = Ref}=State)->
	io:format("rnis_data_att_emul_load handle_call1~n"),
	timer:cancel(Ref),
	Atts = load_atts(),
  	ReloadTimeout = application:get_env(rnis_data_att_emul,reload_atts_timeout, ?RELOAD_TIMEOUT),
  	{ok,NewRef} = timer:send_after(ReloadTimeout, reload),
  	{reply, ok, State#state{atts = Atts, timer_ref = NewRef}};
handle_call(handle_reload,_From,#state{atts = Atts,timer_ref = Ref}=State)->
	io:format("rnis_data_att_emul_load 2~n"),
	Atts = load_atts(),
  	{reply, ok, State#state{atts = Atts}};
handle_call(get_atts,_From,#state{atts = Atts}=State)->
	io:format("rnis_data_att_emul_load handle_call3~n"),
  	{reply, {ok,Atts}, State};
handle_call(_Request, _From, State) ->
	io:format("rnis_data_att_emul_load handle_call4~n"),
  	{reply, ok, State}.

handle_cast(_Msg, State) ->
	io:format("rnis_data_att_emul_load handle_cast~n"),
  	{noreply, State}.

handle_info(timeout, State) ->
	io:format("rnis_data_att_emul_load handle_info1~n"),
	Atts = load_atts(),
  	ReloadTimeout = application:get_env(rnis_data_att_emul,reload_atts_timeout, ?RELOAD_TIMEOUT),
  	{ok,Ref} = timer:send_after(ReloadTimeout, reload),
	{noreply, State#state{atts = Atts, timer_ref = Ref}};
handle_info(reload, #state{timer_ref = Ref}=State) ->
	io:format("rnis_data_att_emul_load init handle_info2~n"),
	timer:cancel(Ref),
	Atts = load_atts(),
	ReloadTimeout = application:get_env(rnis_data_att_emul,reload_atts_timeout, ?RELOAD_TIMEOUT),
	{ok,NewRef} = timer:send_after(ReloadTimeout, reload),
	{noreply, State#state{atts = Atts, timer_ref = NewRef}};
handle_info(_Info, State) ->
	io:format("rnis_data_att_emul_load handle_info3~n"),
	{noreply, State}.

terminate(_Reason, _State) ->
	io:format("rnis_data_att_emul_load terminate~n"),
	ok.

code_change(_OldVsn, State, _Extra) ->
	io:format("rnis_data_att_emul_load code_change~n"),
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

load_atts()->
	[1,2,3,4,5].
	%rpc:call(?NODE,mnesia,dirty_all_keys,[]).
	