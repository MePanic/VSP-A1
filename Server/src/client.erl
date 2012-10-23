-module(client).
-compile(export_all).
-import(werkzeug).

-record(state, {clNr,servName,startTime,sendItv,sendCounter,gotAll}).

%Startfunktion ohne Node
start() ->
			{ok, CfgList} = file:consult("client.cfg"),
			{ok, ClientsNr} = werkzeug:get_config_value(clients, CfgList),
			lists:map(fun(X)->spawn(fun()->init(X,CfgList,node()) end) end,lists:seq(1,ClientsNr)).

%Startfunktion mit Node
start(Node) ->
			{ok, CfgList} = file:consult("client.cfg"),
			{ok, ClientsNr} = werkzeug:get_config_value(clients, CfgList),
			lists:map(fun(X)->spawn(fun()->init(X,CfgList,Node) end) end,lists:seq(1,ClientsNr)).	
	
%Initialisierung 
init(Number,CfgList,Node) -> 
			{ok, Lifetime} = werkzeug:get_config_value(lifetime, CfgList),
			CPID=self(),
			%Beendet den Client nach der Lebenszeit
			spawn(fun()->timer:kill_after(Lifetime*1000,CPID) end),													
			{ok, ServName} = werkzeug:get_config_value(servername, CfgList),
			{ok, SendItv} = werkzeug:get_config_value(sendeintervall, CfgList),
			%Client beginnt als Redakteur
			loopEdit(#state{clNr=Number,servName={ServName,Node},sendItv=SendItv,sendCounter=0,gotAll=false}).		

	
%Schleife für den Leser
%Wenn das GotAll-Flag gesetzt ist, wird in den Redakteur-Zustand gewechselt, ansonsten wird eine Nachricht angefordert
loopRead(S= #state{gotAll=GotAll}) ->
            if  GotAll==true ->
				loopEdit(S#state{gotAll=false});
			true ->
				loopRead(getMessage(S))
            end.
			
%Schleife für den Redakteur
%Wenn bereits 5 ( >4 ) Nachrichten gesendet wurden, wird in den Leser-Zustand gewechselt, der Counter auf 0 gesetzt und ein neues 
%Sendeintervall berechnet, ansonsten wird eine Nachricht gesendet und der Couter inkrementiert
loopEdit(S= #state{sendItv=SendItv,sendCounter=SendCounter})->            
            if SendCounter > 4 ->
				loopRead(S#state{sendCounter=0,sendItv=randomItv(SendItv)});
            true ->
				sendMessage(S),
				loopEdit(S#state{sendCounter=SendCounter+1})
            end.
	
%Hilfsfunktion für den Redakteur zum Senden von Nachrichten
%Mit der angeforderten Nachrichtennummer wird eine Nachricht erstellt und an den Server geschickt. Danach wird der Thread für das 
%Sendeintervall pausiert und die Nachricht in das Log geschrieben
sendMessage(#state{clNr=ClNr,sendItv= SendItv, servName = ServName}) -> 
            Id = getMsgId(ServName),
            Msg = lists:concat([net_adm:localhost(),":2-TeamNr-Client",ClNr,": ",Id,". Msg. Time: ", werkzeug:timeMilliSecond(),"|"]),
            ServName ! {dropmessage,{Msg,Id}},
			timer:sleep(round(SendItv * math:pow(10,3))),
            werkzeug:logging( log_file_name(ClNr), lists:concat([Msg,io_lib:nl()])).
			
			
%Hilfsfunktion für den Leser zum Empfangen von Nachrichten
getMessage(S=#state{clNr=ClNr,servName=ServName}) -> 
			ServName ! {getmessages, self()},
            receive {Msg,GotAll} -> 
				werkzeug:logging(log_file_name(ClNr), lists:concat([Msg,"ArvTime Client: ",werkzeug:timeMilliSecond(),io_lib:nl()] )),
				S#state{gotAll=GotAll}
            end.
			
%Fordert die aktuelle Nachrichtennummer vom Server an
getMsgId(ServName) -> 
			ServName ! {getmsgid,self()},
			receive Id -> Id
			end.
			
			
%Generiert den Namen für das Log des aktuellen Clients
log_file_name(ClNr) -> lists:concat(["client_",ClNr,net_adm:localhost(),".log"]).
			
			
%Generiert ein neues Sendeintervall
randomItv(SendItv) -> 
			Itv = SendItv + newDt(SendItv),
			if Itv < 1 -> 1;
			true -> Itv
			end.
	
%Hilfsfunktion für randomItv
newDt(SendItv) ->
			Dt = (random:uniform() - 0.5) * SendItv,
			if (Dt < 0) and (Dt > -1) -> -1;
			(Dt >= 0) and (Dt < 1) -> 1;
			true -> Dt
			end.
			