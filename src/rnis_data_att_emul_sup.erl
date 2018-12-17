-module(rnis_data_att_emul_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    RestartStrategy = one_for_all,
    MaxRestarts = 5,
    MaxSecondsBetweenRestarts = 10,
    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    AttsDataLoad = {
        rnis_data_att_emul_load,
        {rnis_data_att_emul_load, start_link, []},
        permanent, 5000, worker, [rnis_data_att_emul_load]},
    EmulServer = {
        rnis_data_att_emul_server,
        {rnis_data_att_emul_server, start_link, []},
        permanent, 5000, worker, [rnis_data_att_emul_server]},
	DataGenerate = {
        rnis_data_att_emul_generate,
        {rnis_data_att_emul_generate, start_link, []},
        permanent, 5000, worker, [rnis_data_att_emul_generate]},
    ToStart = [AttsDataLoad, EmulServer,DataGenerate],
    {ok, {SupFlags, ToStart}}.