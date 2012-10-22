%% Copyright
-module(server).
-author("Administrator").

%% API
-export([start/1]).

start(Name) ->
  ServerPid = spawn(fun() -> loopServ(0,dict:new(),dict:new(),dict:new()) end),
  register(Name,ServerPid),
  ServerPid.

loopServ(X,HoldBackQ,DeliveryQ,C) ->
  Clients = checkClients(C),
  receive
    {getmsgid,PID} ->                   PID ! {X+1},
                                        loopServ(X+1,HoldBackQ,DeliveryQ,Clients);
    {dropmessage,{Nachricht,Nummer}} -> HBQ1 = dict:store(Nummer,Nachricht,HoldBackQ),
                                        {HBQ,DLQ} = checkHBQ(HBQ1,DeliveryQ),
                                        loopServ(X,HBQ,DLQ,Clients);
    {getmessages,PID} ->                {Num,Clients1}  = get(PID,Clients),
                                        PID ! {dict:fetch(Num,DeliveryQ),wasLast(Num,DeliveryQ)},
                                        loopServ(X,HoldBackQ,DeliveryQ,Clients1)
  end.

wasLast(Num,DeliveryQ) -> Temp = lists:max(dict:fetch_keys(DeliveryQ))+1,if
                            Temp > Num -> true;
                            true -> false
                          end.

checkHBQ(HoldBackQ,DeliveryQ) -> Min = lists:min(dict:fetch_keys(HoldBackQ)),
                                 case dict:find(Min+1,HoldBackQ) of
                                      error -> {HoldBackQ,DeliveryQ};
                                      Val -> eraseOverhead(dict:erase(Min,HoldBackQ),dict:store(Min,dict:fetch(Min,HoldBackQ),DeliveryQ))
                                 end.

eraseOverhead(HoldBackQ,DeliveryQ) -> MaxTexts = getConfigMaxTexts(),
                                      MaxTextsHB = MaxTexts/2,
                                      KeysH = dict:fetch_keys(HoldBackQ),
                                      ResH = eraseSomething(MaxTextsHB,lists:min(KeysH),HoldBackQ),
                                      KeysD = dict:fetch_keys(HoldBackQ),
                                      SizeD = lists:size(KeysD),
                                      if
                                          SizeD >= MaxTexts -> ResD = dict:erase(lists:min(KeysD),DeliveryQ);
                                          true -> ResD = DeliveryQ
                                      end,
                                      {ResH,ResD}.

eraseSomething(Max,MinKey,HBQ) ->
  Keys = dict:fetch_keys(HBQ),
  Size = lists:max(Keys)-lists:min(Keys),
  if
      Size >= Max -> eraseSomething(Max,MinKey,dict:erase(lists:min(MinKey),HBQ));
      true -> io:format("*** Fehlernachricht fuer Nachrichtennummern ~p bis ~p um ~p~n",[MinKey,lists:min(Keys)-1,erlang:now()]),HBQ
  end.




get(PID,Clients) -> Val = dict:find(PID,Clients),
                     if
                        is_integer(Val) -> {Val,dict:store(PID,{Val+1,erlang:now()},Clients)};
                        true -> {0,dict:store(PID,{0,erlang:now()},Clients)}
                     end.

checkClients(C) ->  ConfigTime = getConfigTime(),
                    Fun = fun({Key,{Val,Time}}) ->
                                {D1,T1} = calendar:time_difference(Time,erlang:now()),
                                if D1 /= 0 -> false;
                                true -> if T1 > ConfigTime -> false;
                                        true -> true
                                        end
                                end
                          end,
                    dict:filter(Fun,C).

getConfigTime() -> notImplemented .

getConfigMaxTexts() -> notImplemented .
