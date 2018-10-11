%%%-------------------------------------------------------------------
%%% @author Vladimir G. Sekissov <eryx67@gmail.com>
%%% @copyright (C) 2018, Vladimir G. Sekissov
%%% @doc
%%% Example of `psq' usage for spreading jobs between workers identified by `pid'
%%% @end
%%% Created : 11 Oct 2018 by Vladimir G. Sekissov <eryx67@gmail.com>
%%%-------------------------------------------------------------------
-module(pid_psq).

-export([new/0, add/2, add/3, delete/2, peek_min/1, get_min/1, inc_priority/2, dec_priority/2]).

-spec new() -> psq:psq().
new() ->
    psq:new().

-spec add(any(), psq:psq()) -> psq:psq().
add(Pid, PSQ) ->
    add(Pid, 0, PSQ).

-spec add(pid(), psq:priority(), psq:psq()) -> psq:psq().
add(Pid, Prio, PSQ) ->
    Key = pid_to_int(Pid),
    psq:insert(Key, Prio, Pid, PSQ).

-spec delete(pid(), psq:psq()) -> psq:psq().
delete(Pid, PSQ) ->
    Key = pid_to_int(Pid),
    psq:delete(Key, PSQ).

-spec peek_min(psq:psq()) -> undefined | {ok, pid()}.
peek_min(PSQ) ->
    maybe(psq:find_min(PSQ), undefined, fun ({_, _, Pid}) -> {ok, Pid} end).

%% @doc Get pid with minimal priority and increase its priority by 1.
-spec get_min(psq:psq()) -> undefined | {ok, {pid(), psq:psq()}}.
get_min(PSQ) ->
    {Res, PSQ1} = psq:alter_min(fun ({just, {K, P, Pid}}) ->
                                        {{just, Pid}, {just, {K, P+1, Pid}}};
                                    (nothing) ->
                                        nothing
                                end, PSQ),
    maybe(Res, undefined, fun (Pid) -> {ok, {Pid, PSQ1}} end).

-spec inc_priority(pid(), psq:psq()) -> undefined | {ok, psq:psq()}.
inc_priority(Pid, PSQ) ->
    upd_priority(Pid, fun (P) -> P + 1 end, PSQ).

-spec dec_priority(pid(), psq:psq()) -> undefined | {ok, psq:psq()}.
dec_priority(Pid, PSQ) ->
    upd_priority(Pid, fun (P) -> P - 1 end, PSQ).

upd_priority(Pid, SetF, PSQ) ->
    Key = pid_to_int(Pid),
    {Res, PSQ1} = psq:alter(fun ({just, {P, V}}) ->
                                    {{just, P}, {just, {SetF(P), V}}};
                                (nothing) ->
                                    nothing
                            end, Key, PSQ),
    maybe(Res, undefined, fun (_Prio) -> {ok, PSQ1} end).

maybe(nothing, D, _F) ->
    D;
maybe({just, V}, _D, F) ->
    F(V).

pid_to_int(Pid) ->
    Bin = erlang:term_to_binary(Pid),
    BS = erlang:byte_size(Bin),
    <<Int:BS/unit:8>> = Bin,
    Int.

%%--------------------------
%% Tests
%%--------------------------
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

pid_psq_test_() ->
    {setup,
    fun () ->
            [erlang:make_ref() || _ <- lists:seq(1, 10)]
    end,
    fun (Pids) ->
            Q = lists:foldl(fun pid_psq:add/2, pid_psq:new(), Pids),
            [?_assertEqual(lists:sort([{P, Pid} || {_, P, Pid} <- psq:to_list(Q)]),
                           lists:sort(lists:zip(lists:duplicate(length(Pids), 0), Pids))),
             ?_assertMatch({ok, _}, pid_psq:peek_min(Q)),
             ?_test(
                begin
                    Q1 = lists:foldl(fun (_, Q0) ->
                                            Res = pid_psq:get_min(Q0),
                                            ?assertMatch({ok, {_, _}}, Res),
                                            {ok, {Pid, Q1}} = Res,
                                            ?assert(is_reference(Pid)),
                                            Q1
                                    end, Q, Pids),
                   ?_assertEqual(lists:sort([{P, Pid} || {_, P, Pid} <- psq:to_list(Q1)]),
                                 lists:sort(lists:zip(lists:duplicate(length(Pids), 1), Pids)))
                end),
             ?_test(
                begin
                    Q2 = lists:foldl(fun (Pid, Q0) ->
                                            Res = pid_psq:inc_priority(Pid, Q0),
                                            ?assertMatch({ok, _}, Res),
                                            {ok, Q1} = Res,
                                            Q1
                                    end, Q, Pids),
                   ?_assertEqual(lists:sort([{P, Pid} || {_, P, Pid} <- psq:to_list(Q2)]),
                                 lists:sort(lists:zip(lists:duplicate(length(Pids), 1), Pids))),
                    Q3 = lists:foldl(fun (Pid, Q0) ->
                                            Res = pid_psq:dec_priority(Pid, Q0),
                                            ?assertMatch({ok, _}, Res),
                                            {ok, Q1} = Res,
                                            Q1
                                    end, Q, Pids),
                   ?_assertEqual(lists:sort([{P, Pid} || {_, P, Pid} <- psq:to_list(Q3)]),
                                 lists:sort(lists:zip(lists:duplicate(length(Pids), 0), Pids)))
                end)
            ]
    end
    }.

-endif.