-module(rnis_data_att_emul_generate).

-behaviour(gen_server).

%% API
-export([start_link/0,
		 handle_generate/0,
		 handle_generate/1,
		 stop/0,
		 data_flow/2]).

%% gen_server callbacks
-export([init/1,
		 handle_call/3,
		 handle_cast/2,
		 handle_info/2,
		 terminate/2,
		 code_change/3]).

-include("rnis_data_att_emul.hrl").

-record(state, {timer_ref}).

%% ====================================================================
%% API functions
%% ====================================================================

start_link() ->
  gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

stop()->
	gen_server:cast(?MODULE, stop).

handle_generate()->
 	gen_server:call(?MODULE, handle_generate).

handle_generate({Id,Port})->
 	gen_server:call(?MODULE, {handle_generate,Id,Port}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
	{ok, #state{},?WAIT_INIT}.

handle_call(handle_generate, _From, State) ->
	case whereis(rnis_data_att_emul_load) of
		undefined ->
			lager:info("rnis_data_att_emul_load not starter", []),
			{reply, not_generate, State};
		_ ->
			{ok,Atts} = rnis_data_att_emul_load:get_atts(),
			data_flow(?FUN_TO_SEND,Atts),
			{reply, ok, State}
	end;
handle_call({handle_generate,Id,Port}, _From, State) ->
	data_flow(?FUN_TO_SEND,[{Id,list_to_atom("att_emul_server_"++integer_to_list(Port))}]),
	{reply, ok, State};
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
	Time = system_time(millisec),
	List = [{Server,{ID, Time,
			 [{<<"lat">>,rand_f(55,56)},{<<"lon">>,rand_f(37,38)},{<<"speed">>,rand_i(0,120)}]}} 
		   || {ID, Server} <- Atts],
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