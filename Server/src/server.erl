%% Copyright
-module(server).

%% API
-export([start/0]).

start() ->
  {ok, Config} = file:consult("server.cfg"),
  {ok, Name} = werkzeug:get_config_value(servername, Config),
  {ok, DlqMax} =   werkzeug:get_config_value(dlqlimit, Config),
  {ok, Difftime} = werkzeug:get_config_value(difftime, Config),
  io:format("DlqMax: ~p~n",[DlqMax]),
  {ok, ClientTimeout} =  werkzeug:get_config_value(clientlifetime, Config),
  io:format("ClientTimeout: ~p~n",[ClientTimeout]),
  ServerPid = spawn(fun() -> loopServ(1,dict:new(),dict:new(),dict:new(),ClientTimeout,DlqMax,Difftime) end),
  register(Name,ServerPid),
  %%werkzeug:logging("NServer.log",lists:concat([appendTimeStamp("Server Startzeit: ", " mit PID "),self(),io_lib:nl()])),
  client:start(),
  %%ServerPid ! {getmsgid,ServerPid},
  ServerPid.

loopServ(X,HoldBackQ,DeliveryQ,C,ClientTimeout,DlqMax,Difftime) ->
  Clients = checkClients(C,ClientTimeout),
  io:format("debug2~n"),
  receive
    {getmsgid,PID} ->
      io:format("debug3~n"),               PID ! X,
                                        werkzeug:logging("NServer.log",lists:concat(["Server: Nachrichtennummer ",X," gesendet~n",io_lib:nl()])),
                                        loopServ(X+1,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax,Difftime);


%%    {1} -> io:format("geht1~n"), self() ! {dropmessage,{"blablabla1",1}},loopServ(X,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax);
%%    {2} -> io:format("geht2~n"), self() ! {dropmessage,{"blablabla2",2}},loopServ(X,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax);
%%    {3} -> io:format("geht3~n"),loopServ(X,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax);


%%    {dropmessage,{Nachricht,3}} ->  self() ! {getmessages,self()};


    {dropmessage,{Nachricht,Nummer}} ->
      io:format("storing text;~n"),
      %%einmal mit length ausgeben versuchen
      %%io:format("old; ~p~n",[lists:concat(dict:fetch_keys(HoldBackQ))]),
      HBQ1 = dict:store(Nummer,Nachricht,HoldBackQ),
      io:format("new; ~p~n",[lists:concat(dict:fetch_keys(HBQ1))]),
                                        {HBQ,DLQ} = checkQs(HBQ1,DeliveryQ,DlqMax),
                                        werkzeug:logging("NServer.log",lists:concat([appendTimeStamp(Nachricht, "Empfangszeit"),"-dropmessage",io_lib:nl()])),


%%      self() ! {getmsgid,self()},

                                        loopServ(X,HBQ,DLQ,Clients,ClientTimeout,DlqMax,Difftime);
%%    {Text,false} ->  io:format("getmsg~p~n",[Text]),self() ! {getmessages,self()};
%%    {Text,true} ->  io:format("fertig~n");

    {getmessages,PID} ->
      io:format("debug5~n"),              {Num,Clients1}  = get(PID,Clients),
                                        PID ! {dict:fetch(Num,DeliveryQ),wasLast(Num,DeliveryQ)},
                                        loopServ(X,HoldBackQ,DeliveryQ,Clients1,ClientTimeout,DlqMax,Difftime);
    _ ->    io:format("nicht verstanden~n")

    after (Difftime*1000)  -> io:format("Server Ende.~n"),exit(normal)
  end.

wasLast(Num,DeliveryQ) -> Temp = lists:max(dict:fetch_keys(DeliveryQ))+1,if
                            Temp > Num -> true;
                            true -> false
                          end.


%%prüft ob nächste nachricht in der hbq für dlq verfügbar ist, wenn nicht prüft er die größen der qs
checkQs(HoldBackQ,DeliveryQ,DlqMax) -> Keys = dict:fetch_keys(DeliveryQ),
                                       if Keys == [] -> Min = 1;
                                          true -> Min = (lists:max(dict:fetch_keys(DeliveryQ))+1)
                                       end,
                                io:format("CheckQs mit min ~p: ~n",[Min]),
                                 case dict:find(Min,HoldBackQ) of
                                      error -> checkSize(HoldBackQ,DeliveryQ,DlqMax);
                                      {ok,Val} -> checkQs(dict:erase(Min,HoldBackQ),dict:store(Min,dict:fetch(Min,HoldBackQ),DeliveryQ),DlqMax)
                                 end.

checkSize(HoldBackQ,DeliveryQ,DlqMax) ->
  io:format("CheckSize ~n"),
  ResD = checkDLQ(DeliveryQ,DlqMax),
  ResH = checkHBQ(HoldBackQ,ResD,DlqMax),
  {ResH,ResD}.

checkDLQ(DeliveryQ,DlqMax) ->
  io:format("CheckDLQ ~n"),
  KeysD = dict:fetch_keys(DeliveryQ),
  SizeD = erlang:length(KeysD),
  if
    SizeD >= DlqMax ->
      io:format("Erase DLQ ~p ~n",[lists:min(KeysD)]),checkDLQ(dict:erase(lists:min(KeysD),DeliveryQ),DlqMax);
    true -> DeliveryQ
  end.

checkHBQ(HoldBackQ,DeliveryQ,DlqMax) ->
  io:format("CheckHBQ ~n"),
  KeysH = dict:fetch_keys(HoldBackQ),
  SizeH = erlang:length(KeysH),
  Max = DlqMax/2,
  if KeysH == [] -> HoldBackQ;
true ->
  MinK = lists:min(KeysH),
  if
      SizeH >= Max -> ResH = dict:erase(lists:min(KeysH),HoldBackQ),
                      io:format("*** Fehlernachricht fuer Nachrichtennummern ~p bis ~p um ~p~n",[MinK,lists:min(dict:fetch_keys(ResH))-1,erlang:now()]),
                      checkQs(ResH,DeliveryQ,DlqMax);
      true -> HoldBackQ
  end end.

get(PID,Clients) -> Val = dict:find(PID,Clients),
                     if
                        is_integer(Val) -> {Val,dict:store(PID,{Val+1,erlang:now()},Clients)};
                        true -> {0,dict:store(PID,{0,erlang:now()},Clients)}
                     end.

checkClients(C,ClientTimeout) ->
  S = dict:size(C),
if  S < 1 -> C;
true ->
  io:format("debug12~n"),
                    Fun = fun({Key,{Val,Time}}) ->
                      (Time - werkzeug:timeMilliSecond()) <  ClientTimeout
                          end,
  io:format("debug13~n"),
                    dict:filter(Fun,C),
io:format("debug14~n"),0 end.

log(Log) -> spawn( fun() -> io:format(Log),file:write_file("NServer.log",Log,[append])end).


appendTimeStamp(Message,Type) ->
  lists:concat([Message," ",Type,": ",werkzeug:timeMilliSecond(),"|"]).