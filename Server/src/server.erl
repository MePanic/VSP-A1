%% Copyright
-module(server).

%% API
-export([start/0]).

start() ->
  {ok, Config} = file:consult("server.cfg"),
  {ok, Name} = werkzeug:get_config_value(servername, Config),
  {ok, DlqMax} =   werkzeug:get_config_value(dlqlimit, Config),
  io:format("DlqMax: ~p~n",[DlqMax]),
  {ok, ClientTimeout} =  werkzeug:get_config_value(clientlifetime, Config),
  io:format("ClientTimeout: ~p~n",[ClientTimeout]),
  ServerPid = spawn(fun() -> loopServ(1,dict:new(),dict:new(),dict:new(),ClientTimeout,DlqMax) end),
  %%register(Name,self()),
  %%werkzeug:logging("NServer.log",lists:concat([appendTimeStamp("Server Startzeit: ", " mit PID "),self(),io_lib:nl()])),
  %%client:start(),
  ServerPid ! {getmsgid,ServerPid},
  ServerPid.

loopServ(X,HoldBackQ,DeliveryQ,C,ClientTimeout,DlqMax) ->
  Clients = checkClients(C,ClientTimeout),
  io:format("debug2~n"),
  receive
    {getmsgid,PID} ->
      io:format("debug3~n"),               PID ! {X},
                                        werkzeug:logging("NServer.log",lists:concat(["Server: Nachrichtennummer ",X," gesendet~n",io_lib:nl()])),
                                        loopServ(X+1,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax);


%%    {1} -> io:format("geht1~n"), self() ! {dropmessage,{"blablabla1",1}},loopServ(X,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax);
%%    {2} -> io:format("geht2~n"), self() ! {dropmessage,{"blablabla2",2}},loopServ(X,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax);
%%    {3} -> io:format("geht3~n"),loopServ(X,HoldBackQ,DeliveryQ,Clients,ClientTimeout,DlqMax);


%%    {dropmessage,{Nachricht,3}} ->  self() ! {getmessages,self()};


    {dropmessage,{Nachricht,Nummer}} ->
      io:format("storing text;~n"),io:format("old; ~p~n",[lists:concat(dict:fetch_keys(HoldBackQ))]), HBQ1 = dict:store(Nummer,Nachricht,HoldBackQ),io:format("new; ~p~n",[lists:concat(dict:fetch_keys(HBQ1))]),
                                        {HBQ,DLQ} = checkHBQ(HBQ1,DeliveryQ,DlqMax),
                                        werkzeug:logging("NServer.log",lists:concat([appendTimeStamp(Nachricht, "Empfangszeit"),"-dropmessage",io_lib:nl()])),


%%      self() ! {getmsgid,self()},

                                        loopServ(X,HBQ,DLQ,Clients,ClientTimeout,DlqMax);
%%    {Text,false} ->  io:format("getmsg~p~n",[Text]),self() ! {getmessages,self()};
%%    {Text,true} ->  io:format("fertig~n");

    {getmessages,PID} ->
      io:format("debug5~n"),              {Num,Clients1}  = get(PID,Clients),
                                        PID ! {dict:fetch(Num,DeliveryQ),wasLast(Num,DeliveryQ)},
                                        loopServ(X,HoldBackQ,DeliveryQ,Clients1,ClientTimeout,DlqMax);
    _ ->    io:format("nicht verstanden~n")
  end.

wasLast(Num,DeliveryQ) -> Temp = lists:max(dict:fetch_keys(DeliveryQ))+1,if
                            Temp > Num -> true;
                            true -> false
                          end.

checkHBQ(HoldBackQ,DeliveryQ,DlqMax) -> Min = lists:min(dict:fetch_keys(HoldBackQ)),
                                io:format("CheckHBQ ~n"),

                                 case dict:find(Min+1,HoldBackQ) of
                                      error -> eraseOverhead(HoldBackQ,DeliveryQ,DlqMax);
                                      Val -> checkHBQ(dict:erase(Min,HoldBackQ),dict:store(Min,dict:fetch(Min,HoldBackQ),DeliveryQ),DlqMax)
                                 end.

eraseOverhead(HoldBackQ,DeliveryQ,DlqMax) ->
                                      Min = lists:min(dict:fetch_keys(HoldBackQ)),
                                      Max = lists:max(dict:fetch_keys(HoldBackQ)),
  io:format("Too Big,erase messages~n"),
                                      if Min =/= Max ->
                                      MaxTextsHB = DlqMax/2,
                                      KeysH = dict:fetch_keys(HoldBackQ),
  io:format("old: ~p~n",lists:concat([KeysH])),
                                      ResH = eraseSomething(MaxTextsHB,lists:min(KeysH),lists:min(KeysH),HoldBackQ),
                                      KeysD = dict:fetch_keys(DeliveryQ),
                                      SizeD = erlang:length(KeysD),
  Keysx = dict:fetch_keys(ResH),
  io:format("new: ~p~n",lists:concat([Keysx])),
                                       if
                                         SizeD >= DlqMax -> ResD = dict:erase(lists:min(KeysD),DeliveryQ),eraseOverhead(ResH,ResD,DlqMax);
                                         true -> ResD = DeliveryQ
                                       end,
                                      {ResH,ResD};
                                      true ->
                                      if
                                          SizeD >= DlqMax -> ResD = dict:erase(lists:min(KeysD),DeliveryQ),eraseOverhead(ResH,ResD,DlqMax);
                                          true -> ResD = DeliveryQ
                                      end,
                                      {ResH,ResD}end.

eraseSomething(Max,MinKey,HBQ) ->
  Keys = dict:fetch_keys(HBQ),
  Size = lists:max(Keys)-lists:min(Keys),
  if
      Size >= Max -> eraseSomething(Max,MinKey,dict:erase(lists:min(MinKey),HBQ));
      true -> io:format("*** Fehlernachricht fuer Nachrichtennummern ~p bis ~p um ~p~n",[MinKey,lists:min(Keys),erlang:now()]),HBQ
  end.




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


getConfigTime() -> notImplemented .

getConfigMaxTexts() -> notImplemented .


log(Log) -> spawn( fun() -> io:format(Log),file:write_file("NServer.log",Log,[append])end).


appendTimeStamp(Message,Type) ->
  lists:concat([Message," ",Type,": ",werkzeug:timeMilliSecond(),"|"]).