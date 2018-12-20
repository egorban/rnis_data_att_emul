-module(rnis_data_att_emul_generate).

-behaviour(gen_server).

%% API
-export([start_link/0,
		 data_flow/2]).

%% gen_server callbacks
-export([init/1,
		 handle_call/3,
		 handle_cast/2,
		 handle_info/2,
		 terminate/2,
		 code_change/3]).

-define(TIMEPERIOD, 270000). %ms, 4.5 min
-define(FUN_TO_SEND, fun rnis_data_att_emul_server:add_data/1).
-define(WAIT_INIT, 1000). %ms

-record(state, {timer_ref}).

%% ====================================================================
%% API functions
%% ====================================================================

start_link() ->
  gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

stop()->
	gen_server:cast(?MODULE, stop).

%% handle_generate()->
%% 	gen_server:cast(?MODULE, handle_generate).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
	{ok, #state{}, 0}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(timeout, State) ->
	case whereis(rnis_data_att_emul_load) of
		undefined ->
			lager:info("rnis_data_att_emul_load not starter", []),
			{noreply, State,?WAIT_INIT};
		_ ->
			{ok,Atts} = rnis_data_att_emul_load:get_atts(),
			data_flow(?FUN_TO_SEND,Atts),
			TimePeriod = application:get_env(rnis_data_att_emul,generate_period, ?TIMEPERIOD),
			{ok,TRef} = timer:send_after(TimePeriod, generate),
			{noreply, State#state{timer_ref=TRef}}
	end;
handle_info(generate, #state{timer_ref=TRef}=State) ->
	timer:cancel(TRef),
	case whereis(rnis_data_att_emul_load) of
		undefined ->
			lager:info("rnis_data_att_emul_load not starter", []),
			{noreply, State,?WAIT_INIT};
		_ ->
			{ok,Atts} = rnis_data_att_emul_load:get_atts(),
			data_flow(?FUN_TO_SEND,Atts),
			TimePeriod = application:get_env(rnis_data_att_emul,generate_period, ?TIMEPERIOD),
			{ok,NewTRef} = timer:send_after(TimePeriod, generate),
			{noreply, State#state{timer_ref=NewTRef}}
	end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

data_flow(Fun, Atts)->
	lager:info("Generate Data for ~p Atts", [length(Atts)]),
	List = [{ID, system_time(millisec),
			 [{<<"lat">>,rand_f(55,56)},{<<"lon">>,rand_f(37,38)},{<<"speed">>,rand_i(0,120)}]} 
		   || ID <- Atts],
	lists:foreach(Fun, List).

rand_f(Min,Max)->
 	State = case random:seed(now()) of
 				undefined -> random:seed(now());
 				V -> V 
 			end,
	{R,_} = random:uniform_s(State),
 	Min+(Max-Min)*R.

rand_i(Min,Max)->
 	State = case random:seed(now()) of
 				undefined -> random:seed(now());
 				V -> V 
 			end,
	{R,_} = random:uniform_s(State),
 	round(Min+(Max-Min)*R).	

system_time(millisec)->
    system_time(millisec,os:timestamp()).

system_time(millisec,{Mega,S,Micro})->
    (Mega*1000000+S)*1000+(Micro div 1000).