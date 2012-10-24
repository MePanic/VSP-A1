%% Copyright
-module(server).

%% API
-export([start/0]).

start() ->
  {ok, Config} = file:consult("server.cfg"),
  {ok, Name} = werkzeug:get_config_value(servername, Config),
  {ok, DlqMax} =   werkzeug:get_config_value(dlqlimit, Config),
  {ok, Difftime} = werkzeug:get_config_value(difftime, Config),
  {ok, ClientTimeout} =  werkzeug:get_config_value(clientlifetime, Config),
  ServerPid = spawn(fun() -> loopServ(1,dict:new(),dict:new(),dict:new(),ClientTimeout,DlqMax,Difftime) end),
  register(Name,ServerPid),
  %%werkzeug:logging("NServer.log",lists:concat([appendTimeStamp("Server Startzeit: ", " mit PID "),ServerPid,io_lib:nl()])),
  client:start(),
  ServerPid.

loopServ(X,HoldBackQ,DeliveryQ,C,ClientTimeout,DlqMax,Difftime) ->
  Clients = checkClients(C,ClientTimeout),
  receive
    {getmsgid,PID} ->                   PID ! X,
                                        werkzeug:logging("NServer.log",lists:concat(["Server: Nachrichtennummer ",X," gesendet",io_lib:nl()])),
                                        loopServ(X+1,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax,Difftime);


    {dropmessage,{Nachricht,Nummer}} -> HBQ1 = dict:store(Nummer,Nachricht,HoldBackQ),
                                        {HBQ,DLQ} = checkQs(HBQ1,DeliveryQ,DlqMax),
                                        werkzeug:logging("NServer.log",lists:concat([appendTimeStamp(Nachricht, "Empfangszeit"),"-dropmessage",io_lib:nl()])),
                                        loopServ(X,HBQ,DLQ,Clients,ClientTimeout,DlqMax,Difftime);

    {getmessages,PID} ->
                                        {Num,Clients1}  = get(PID,Clients),
                                        DelMin = lists:min(dict:fetch_keys(DeliveryQ)),
                                        if
                                          Num >= DelMin ->
                                              PID ! {dict:fetch(Num,DeliveryQ),wasLast(Num,DeliveryQ)},
                                              loopServ(X,HoldBackQ,DeliveryQ,Clients1,ClientTimeout,DlqMax,Difftime);
                                          true ->
                                              ResC = dict:store(PID,{DelMin+1,timestamp()},Clients1),
                                              PID ! {dict:fetch(DelMin,DeliveryQ),wasLast(DelMin,DeliveryQ)},io:format("gesendet2 ~n"),
                                              loopServ(X,HoldBackQ,DeliveryQ,ResC,ClientTimeout,DlqMax,Difftime)
                                        end;

    _ ->    io:format("nicht verstanden~n")

    after (Difftime*1000)  -> io:format("Server Ende.~n"),exit(normal)
  end.



wasLast(Num,DeliveryQ) -> Temp = lists:max(dict:fetch_keys(DeliveryQ)),
                            Temp == Num.


%%prüft ob nächste nachricht in der hbq für dlq verfügbar ist, wenn nicht prüft er die größen der qs
checkQs(HoldBackQ,DeliveryQ,DlqMax) -> Keys = dict:fetch_keys(DeliveryQ),
                                       if Keys == [] -> Min = 1;
                                          true -> Min = (lists:max(dict:fetch_keys(DeliveryQ))+1)
                                       end,
                                       case dict:find(Min,HoldBackQ) of
                                            error -> checkSize(HoldBackQ,DeliveryQ,DlqMax);
                                            {ok,Val} -> checkQs(dict:erase(Min,HoldBackQ),dict:store(Min,dict:fetch(Min,HoldBackQ),DeliveryQ),DlqMax)
                                       end.

checkSize(HoldBackQ,DeliveryQ,DlqMax) ->
  {ResH,ResD} = checkHBQ(HoldBackQ,checkDLQ(DeliveryQ,DlqMax),DlqMax),
  {ResH,ResD}.

checkDLQ(DeliveryQ,DlqMax) ->
  KeysD = dict:fetch_keys(DeliveryQ),
  SizeD = erlang:length(KeysD),
  if
    SizeD >= DlqMax ->
      io:format("Erase DLQ ~p ~n",[lists:min(KeysD)]),checkDLQ(dict:erase(lists:min(KeysD),DeliveryQ),DlqMax);
    true -> DeliveryQ
  end.

checkHBQ(HoldBackQ,DeliveryQ,DlqMax) ->
  KeysH = dict:fetch_keys(HoldBackQ),
  SizeH = erlang:length(KeysH),
  Max = DlqMax/2,
  if KeysH == [] -> {HoldBackQ,DeliveryQ};
true ->
  MinK = lists:min(KeysH),
  if
      SizeH >= Max -> ResH = dict:erase(lists:min(KeysH),HoldBackQ),
                      ResD = dict:store(MinK,dict:fetch(MinK,HoldBackQ),DeliveryQ),
                      io:format("*** Fehlernachricht fuer Nachrichtennummern ~p bis ~p um ~p~n",[lists:max(dict:fetch_keys(DeliveryQ))+1,lists:min(dict:fetch_keys(ResH))-2,erlang:now()]),
                      checkQs(ResH,ResD,DlqMax);
      true -> {HoldBackQ,DeliveryQ}
  end end.


get(PID,Clients) -> case dict:find(PID,Clients) of
    error -> {1,dict:store(PID,{1,timestamp()},Clients)};
    {ok,{Val,_}} when is_integer(Val)  -> {Val,dict:store(PID,{Val+1,timestamp()},Clients)}
  end.

checkClients(C,ClientTimeout) ->
  S = dict:size(C),
if  S < 1 -> C;
true ->
  io:format("Hier sollte gefiltert werden~n"),C end.
                    %%dict:filter(fun(_,{_,Time}) ->  (timestamp()- Time) <  ClientTimeout end,C) end.
%%orddict:filter(fun(_,{_,Timestamp}) -> (timestamp() - Timestamp) < ClientTimeout end,C) end.

timestamp() ->
  {Mega, Secs, _} = now(),
  Mega*1000000 + Secs.

%%log(Log) -> spawn( fun() -> io:format(Log),file:write_file("NServer.log",Log,[append])end).


appendTimeStamp(Message,Type) ->
  lists:concat([Message," ",Type,": ",werkzeug:timeMilliSecond(),"|"]).