-module(rnis_data_att_emul_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _StartArgs) ->
    rnis_data_att_emul_sup:start_link().

stop(_State) ->
    ok.


