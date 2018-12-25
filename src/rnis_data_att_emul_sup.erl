-module(rnis_data_att_emul_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-include("rnis_data_att_emul.hrl").

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 5,
    MaxSecondsBetweenRestarts = 10,
    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    AttsDataLoad = {
        rnis_data_att_emul_load,
        {rnis_data_att_emul_load, start_link, []},
        permanent, 5000, worker, [rnis_data_att_emul_load]},
    EmulServersSup = [{
        rnis_data_att_emul_server_sup,
        {rnis_data_att_emul_server_sup, start_link, [[Port]]},
        permanent, 5000, supervisor, [rnis_data_att_emul_server_sup]}||Port<-[P||{_,{_,P}}<-?PREFIX]],
	DataGenerate = {
        rnis_data_att_emul_generate,
        {rnis_data_att_emul_generate, start_link, []},
        permanent, 5000, worker, [rnis_data_att_emul_generate]},
    ToStart = [AttsDataLoad,DataGenerate|EmulServers],
    {ok, {SupFlags, ToStart}}.