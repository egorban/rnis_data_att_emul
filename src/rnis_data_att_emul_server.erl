-module(rnis_data_att_emul_server).

-behaviour(gen_server).

%% API
-export([start_link/0, 
		 stop/0,
		 add_data/1,
		 transmit_data/4]).

%% gen_server callbacks
-export([init/1, 
		 handle_cast/2, 
		 handle_call/3, 
		 handle_info/2, 
		 terminate/2, 
		 code_change/3]).

-include("rnis_data_att_emul_server.hrl").

%% ====================================================================
%% API functions
%% ====================================================================


start_link()->
    gen_server:start_link({local,?MODULE},?MODULE,[],[]).

stop() -> 
	gen_server:cast(?MODULE, stop). 

add_data([]) -> 
    ok;
add_data(Data) when is_list(Data) -> 
    gen_server:call(?MODULE, {add, Data}); 
add_data(Data) when is_tuple(Data)-> 
	gen_server:call(?MODULE, {add, [Data]}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) -> 
	Host = application:get_env(rnis_data_att_emul, rnis_connection_host,?HOST),
  	Port = application:get_env(rnis_data_att_emul, rnis_connection_port,?PORT),
	{ok, Socket} = get_socket(Host, Port, 0), 
	{ok, #state{host = Host, port = Port, socket=Socket}}.

handle_cast(stop, State) -> 
	{stop, normal, State};
handle_cast(_Msg, #state{lastAddTime=LastAddTime} = State) ->
    {noreply, State, get_timeout(LastAddTime)}.

handle_call({add, Data}, _From, #state{counter=Counter, buffer=Buffer} = State)  when Counter >= ?BUFF_SIZE ->
	{reply, ok, send_data(State#state{buffer=[Data|Buffer]})}; 
handle_call({add, Data}, _From, #state{counter=Counter, buffer=Buffer} = State) -> 
	{reply, ok, State#state{counter=Counter+1, lastAddTime=erlang:now(), buffer=[Data|Buffer]}, ?TIMEOUT};
handle_call(_Request, _From, #state{lastAddTime=LastAddTime} = State) ->
    {reply, ok, State, get_timeout(LastAddTime)}.

% Отправка данных по таймауту
handle_info(timeout, State) -> 
    {noreply, send_data(State)};
% События завершения сендеров
handle_info({'DOWN', Ref, process, Pid, normal}, #state{sProcesses=SProcesses, lastAddTime=LastAddTime} = State) -> 
	NewState = State#state{sProcesses=lists:delete({Pid, Ref}, SProcesses)}, 
	NewTimeout = get_timeout(LastAddTime),
	{noreply, NewState, NewTimeout};
handle_info({'DOWN', Ref, process, Pid, Reason}, #state{sProcesses=SProcesses, lastAddTime=LastAddTime} = State) ->
    NewState = State#state{sProcesses=lists:delete({Pid, Ref}, SProcesses)}, 
	NewTimeout = get_timeout(LastAddTime), 
	{noreply, NewState, NewTimeout};
% Закрытие сокета
handle_info({tcp_closed, Socket}, #state{host=Host, port=Port, lastAddTime=LastAddTime} = State) -> 
	gen_tcp:close(Socket),
	{ok, NewSocket} = get_socket(Host, Port, 0),
	NewState = State#state{socket=NewSocket}, 
	NewTimeout = get_timeout(LastAddTime), 
	{noreply, NewState, NewTimeout};
% Входящее tcp сообщение
handle_info({tcp, _Socket, Msg}, #state{lastAddTime=LastAddTime} = State) -> 
	NewTimeout = get_timeout(LastAddTime),
    {noreply, State, NewTimeout};
handle_info(_Info, #state{lastAddTime=LastAddTime} = State) ->
	NewTimeout = get_timeout(LastAddTime),
    {noreply, State, NewTimeout}.

terminate(normal, #state{socket=Socket, sProcesses=[]}) -> 
	gen_tcp:close(Socket),
    ok;
terminate(normal, #state{socket=Socket, sProcesses=SProcesses}) -> 
	timer:sleep(?TERMINATE_TIMEOUT),
	[kill_incomplete(Proc) || Proc <- SProcesses],
	gen_tcp:close(Socket),
	ok;
terminate(Reason, #state{socket=Socket, sProcesses=SProcesses}) -> 
	timer:sleep(?TERMINATE_TIMEOUT),
	[kill_incomplete(Proc) || Proc <- SProcesses],
	gen_tcp:close(Socket),
	ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
 

%% ====================================================================
%% Internal functions
%% ====================================================================

% Получение нового сокета
get_socket(Host, Port, Attempt) when Attempt<?NUMBER_OF_ATTEMPTS -> 
	case gen_tcp:connect(Host, Port, ?TCP_OPTIONS) of 
		{ok, Socket} -> 
			{ok, Socket};
		Error -> 
			timer:sleep(?ATTEMPT_TIMEOUT), 
			get_socket(Host, Port, Attempt+1)
	end.

% Вычисление таймаута до отправки данных возвращает ?TIMEOUT-'время последнего обновления'
get_timeout(undefined) -> 
    infinity;
get_timeout(LastAdd) -> 
	case timer:now_diff(erlang:now(), LastAdd) div 1000 of 
		TimeDiff when 0 < TimeDiff andalso TimeDiff < ?TIMEOUT -> 
			?TIMEOUT - TimeDiff;
		_TimeDiff -> 
			0		
	end.

send_data(#state{buffer=[]} = State) -> 
    State;
send_data(#state{socket=Socket, egtsPacketId=PackID, egtsRecordId=RecId, buffer=Buffer, sProcesses=SProcesses} = State) -> 
	{Pid, Ref} = spawn_monitor(?MODULE, transmit_data, [Socket, PackID, RecId, Buffer]), 
    State#state{
				counter=1, 
				lastAddTime = undefined,
				buffer=[],
				egtsPacketId = PackID + length(Buffer) band 16#ffff, 
				egtsRecordId = RecId + lists:flatlength(Buffer), 
				sProcesses=[{Pid, Ref}|SProcesses]
			   }.

transmit_data(_Socket, _PackID, _RecId, []) -> 
	ok;
transmit_data(Socket, PackID, RecId, [HBuffer|TBuffer]) -> 
	try form_packet(PackID, RecId, HBuffer) of 
		{NewPackID, NewRecId, Packet} -> 
			case gen_tcp:send(Socket, Packet) of 
		        ok -> 
					transmit_data(Socket, NewPackID, NewRecId, TBuffer);
		        {error,closed} -> 
					ok
            end
	catch 
		error:ErrType -> 
			NewPackID = PackID+1 band 16#ffff,
			NewRecId = RecId + length(HBuffer),
	        transmit_data(Socket, NewPackID, NewRecId, TBuffer)
	end.
    

kill_incomplete({Pid, Ref}) -> 
    receive 
        {'DOWN', Ref, process, Pid, normal} -> ok;
        {'DOWN', Ref, process, Pid, Reason} -> 
            error
    after 
        0 -> 
		    exit(Pid, kill),
            killed
    end.
			
% Form packet
form_packet(PackID, RecID, Data) ->
	%%%
    {NewRecID, Records} = form_records(RecID, lists:sort(Data), []), 
    Body = list_to_binary(Records),
    BodyLen = size(Body),
    BCS = crc16(Body),
    Header = 
		<<16#01, 
		  16#00, 
		  16#03, 
		  16#0b, 
		  16#00, 
		  BodyLen:16/little, 
		  PackID:16/little, 
		  ?EGTS_PT_APPDATA>>,
	HCS = crc8(Header),
    Packet = <<Header/binary, HCS, Body/binary, BCS:16/little>>, 
	%%%
    {PackID + 1 band 16#ffff, NewRecID, Packet}.

form_records(RecID, [], Acc) -> 
	{RecID, lists:reverse(Acc)};
form_records(RecID, [{OID, UnixTime, [{<<"lat">>,Lat}, {<<"lon">>,Lon}, {<<"speed">>,Spd}]} | Rest], Acc) -> 
    Time = UnixTime div 1000 - ?TIMESTAMP_20100101_000000_UTC,
	Bear = Abtn = Busy = 0,
    SubRecs = form_subrecs_teledata({OID, UnixTime, Lat, Lon, Spd, Bear, Abtn, Busy}),
    Body = list_to_binary(SubRecs),
    BodySize = size(Body),
    FlagBlock =
        if
%%             PrevOID == OID ->
%%                 <<16#04, Time:32/little>>;
            true ->
                <<16#05, OID:32/little, Time:32/little>>
        end,
    Rec = <<BodySize:16/little, RecID:16/little, FlagBlock/binary,
            ?EGTS_TELEDATA_SERVICE, ?EGTS_TELEDATA_SERVICE, Body/binary>>,
	
	form_records(RecID+1 band 16#ffff, Rest, [Rec|Acc]).

form_subrec_teledata_10({_OID, UnixTime, Latitude, Longitude, Speed, Bearing, Abtn, Busy}) ->
    Time = UnixTime div 1000 - ?TIMESTAMP_20100101_000000_UTC,
    Lat = round(abs(Latitude) / 90 * 16#ffffffff),
    LAHS = if Latitude < 0 -> 1; true -> 0 end,
    Lon = round(abs(Longitude) / 180 * 16#ffffffff),
    LOHS = if Longitude < 0 -> 1; true -> 0 end,
    SpdHi = (round(Speed) * 10) div 256,
    SpdLo = (round(Speed) * 10) rem 256,
    BearHi = round(Bearing) div 256,
    BearLo = round(Bearing) rem 256,
    Odometer = 0,
    DigIns = case Busy of 1 -> 64; _ -> 0 end,
    Source = case Abtn of 1 -> 13; _ -> 0 end,
    SRBody = <<Time:32/little, Lat:32/little, Lon:32/little,
%%  ALTE, LOHS, LAHS, MV, BB, CS, Fix, Vld
    0:1, LOHS:1, LAHS:1, 0:1, 0:1, 0:1, 1:1, 1:1,
    SpdLo:8, BearHi:1, 0:1, SpdHi:6, BearLo:8,
    Odometer:24/little, DigIns:8, Source:8>>,
    SRBodySize = size(SRBody),
    <<16#10, SRBodySize:16/little, SRBody/binary>>.
form_subrecs_teledata({OID, UnixTime, Latitude, Longitude, Speed, Bearing, Abtn, Busy}) ->
    [form_subrec_teledata_10({OID, UnixTime, Latitude, Longitude, Speed, Bearing, Abtn, Busy})].

crc8(Data) ->
    crc8(Data, 16#ff).
crc8(<<Byte:8, Data/binary>>, CheckSum) ->
    crc8(Data, table_crc8(CheckSum bxor Byte));
crc8(_, CheckSum) ->
    CheckSum.
table_crc8(Num) when is_integer(Num) andalso Num > 0 andalso Num < 257 ->
    element(Num + 1, ?CRC8);
table_crc8(_) ->
    0.

crc16(Data) ->
    crc16(Data, 16#FFFF).
crc16(<<S:8, R/binary>>, CRC) ->
    C = (CRC bsl 8) bxor crc16Table((CRC bsr 8) bxor S),
    <<C1:16/unsigned-integer>> = <<C:16/unsigned-integer>>,
    crc16(R, C1);
crc16(_, CRC) ->
    CRC.

crc16Table(I) when is_integer(I) andalso I >= 0 andalso I < 256 ->
    element(I + 1, ?CRC16);
crc16Table(_I) ->
    0.