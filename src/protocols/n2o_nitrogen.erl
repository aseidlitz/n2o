-module(n2o_nitrogen).
-author('Maxim Sokhatsky').
-include_lib("n2o/include/wf.hrl").
-compile(export_all).

% Nitrogen pickle handler

info({init,Rest},Req,State) ->
    Module = State#cx.module,
    InitActions = case Rest of
         <<>> -> Elements = try Module:main() catch X:Y -> wf:error_page(X,Y) end,
                 wf_render:render(Elements),
                 [];
          Binary -> Pid = wf:depickle(Binary),
                    Pid ! {'N2O',self()},
                    receive_actions(Req) end,
    UserCx = try Module:event(init) catch C:E -> wf:error_page(C,E) end,
    Actions = render_actions(wf:actions()),
    {reply,wf:format({io,iolist_to_binary([InitActions,Actions]),<<>>}),Req,wf:context(State,?MODULE,UserCx)};

info({text,Message},Req,State) ->   info(Message,Req,State);
info({binary,Message},Req,State) -> info(binary_to_term(Message,[safe]),Req,State);

info({pickle,_,_,_}=Event, Req, State) ->
    wf:actions([]),
    Result = try html_events(Event,State) catch E:R -> wf:error(?MODULE,"Catch: ~p:~p~n~p", wf:stack(E, R)),
                 {io,render_actions(wf:actions()),<<>>} end,
    {reply,wf:format(Result),Req,State};

info({flush,Actions}, Req, State) ->
    wf:actions([]),
    wf:info(?MODULE,"Flush Message: ~p",[Actions]),
    {reply,wf:format({io,render_actions(wf:actions()),<<>>}),Req, State};

info({direct,Message}, Req, State) ->
    wf:actions([]),
    Module = State#cx.module,
    _Term = try Module:event(Message) catch E:R -> wf:error(?MODULE,"Catch: ~p:~p~n~p", wf:stack(E, R)), <<>> end,
    {reply,wf:format({io,render_actions(wf:actions()),<<>>}),Req,State};

info(Message,Req,State) -> {unknown,Message,Req,State}.

% double render: actions could generate actions

render_actions(Actions) ->
    wf:actions([]),
    First  = wf:render(Actions),
    Second = wf:render(wf:actions()),
    wf:actions([]),
    [First,Second].

% N2O events

html_events({pickle,Source,Pickled,Linked}, State) ->
    Ev = wf:depickle(Pickled),
    case Ev of
         #ev{} -> render_ev(Ev,Source,Linked,State);
         CustomEnvelop -> wf:error("Only #ev{} events for now: ~p",[CustomEnvelop]) end,
    {io,render_actions(wf:actions()),<<>>}.

render_ev(#ev{module=M,name=F,msg=P,trigger=T},_Source,Linked,State) ->
    case F of
         api_event -> M:F(P,Linked,State);
         event -> lists:map(fun({K,V})-> put(K,wf:to_binary(V)) end,Linked), M:F(P);
         _UserCustomEvent -> M:F(P,T,State) end.

receive_actions(Req) ->
    receive
        {actions,A} -> n2o_nitrogen:render_actions(A);
        _ -> receive_actions(Req)
    after 200 ->
         QS = element(14, Req),
         wf:redirect(case QS of <<>> -> ""; _ -> "?" ++ wf:to_list(QS) end),
         [] end.