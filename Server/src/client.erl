-module(client).
-compile(export_all).
-import(werkzeug).

-record(state, {clNr,servName,startTime,sendItv,sendCounter,gotAll}).


start() ->
			{ok, CfgList} = file:consult("client.cfg"),
			{ok, ClientsNr} = werkzeug:get_config_value(clients, CfgList),
			lists:map(fun(X)->spawn(fun()->init(X,CfgList,node()) end) end,lists:seq(1,ClientsNr)).

start(Node) ->
			{ok, CfgList} = file:consult("client.cfg"),
			{ok, ClientsNr} = werkzeug:get_config_value(clients, CfgList),
			lists:map(fun(X)->spawn(fun()->init(X,CfgList,Node) end) end,lists:seq(1,ClientsNr)).	
	
init(Number,CfgList,Node) -> 
			{ok, Lifetime} = werkzeug:get_config_value(lifetime, CfgList),
			CPID=self(),
			spawn(fun()->timer:kill_after(Lifetime*1000,CPID) end),
			{ok, ServName} = werkzeug:get_config_value(servername, CfgList),
			{ok, SendItv} = werkzeug:get_config_value(sendeintervall, CfgList),
			loopEdit(#state{clNr=Number,servName={ServName,Node},sendItv=SendItv,sendCounter=1,gotAll=false}).

	
loopRead(S= #state{gotAll=GotAll}) ->
            if  GotAll==true ->
				loopEdit(S#state{gotAll=false});
			true ->
				loopRead(getMessage(S))
            end.
			
loopEdit(S= #state{sendItv=SendItv,sendCounter=SendCounter})->            
            if SendCounter > 5 ->
				loopRead(S#state{sendCounter=1,sendItv=randomItv(SendItv)});
            true ->
				sendMessage(S),
				loopEdit(S#state{sendCounter=SendCounter+1})
            end.
	
	
sendMessage(#state{clNr=ClNr,sendItv= SendItv, servName = ServName}) -> 
            Id = getMsgId(ServName),
            Msg = lists:concat([net_adm:localhost(),":2-TeamNr-Client",ClNr,": ",Id,". Msg. Time: ", werkzeug:timeMilliSecond(),"|"]),
            ServName ! {dropmessage,{Msg,Id}},
			timer:sleep(round(SendItv * math:pow(10,3))),
            werkzeug:logging( log_file_name(ClNr), lists:concat([Msg,io_lib:nl()])).
			
			
getMessage(S=#state{clNr=ClNr,servName=ServName}) -> 
			ServName ! {getmessages, self()},
            receive {Msg,GotAll} -> 
				werkzeug:logging(log_file_name(ClNr), lists:concat([Msg,"ArvTime Client: ",werkzeug:timeMilliSecond(),io_lib:nl()] )),
				S#state{gotAll=GotAll}
            end.
			
getMsgId(ServName) -> 
			ServName ! {getmsgid,self()},
			receive Id -> Id
			end.
			
			
log_file_name(ClNr) -> lists:concat(["client_",ClNr,net_adm:localhost(),".log"]).
			
			
randomItv(SendItv) -> 
			Itv = SendItv + newDt(SendItv),
			if Itv < 1 -> 1;
			true -> Itv
			end.
	
newDt(SendItv) ->
			Dt = (random:uniform() - 0.5) * SendItv,
			if (Dt < 0) and (Dt > -1) -> -1;
			(Dt >= 0) and (Dt < 1) -> 1;
			true -> Dt
			end.
			