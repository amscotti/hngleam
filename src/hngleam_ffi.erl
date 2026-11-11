-module(hngleam_ffi).
-behaviour(gen_event).
-export([columns/0, rows/0, prepare/0, restore/0, monotonic_ms/0,
         is_darwin/0, process_count/0]).
-export([init/1, handle_event/2, handle_call/2, handle_info/2,
         terminate/2, code_change/3]).

%% Return {some, N} when stdout is a terminal, none otherwise.
columns() ->
    case io:columns() of
        {ok, N} when is_integer(N), N > 0 -> {some, N};
        _ -> none
    end.

rows() ->
    case io:rows() of
        {ok, N} when is_integer(N), N > 0 -> {some, N};
        _ -> none
    end.

%% Remember the terminal settings and restore them if the VM is signalled.
prepare() ->
    save_tty(),
    install_signal_handler(),
    ok.

%% Show the cursor, leave the alternate screen, and put the terminal driver
%% back how it was. Safe to call at any time, including after a crash.
restore() ->
    io:put_chars([27, "[?25h", 27, "[?1049l"]),
    restore_tty(),
    ok.

save_tty() ->
    case os:cmd("stty -g </dev/tty 2>/dev/null") of
        "" -> ok;
        Saved ->
            persistent_term:put(hngleam_tty, string:trim(Saved, both, "\r\n"))
    end.

restore_tty() ->
    case persistent_term:get(hngleam_tty, undefined) of
        undefined ->
            _ = os:cmd("stty sane </dev/tty >/dev/tty 2>/dev/tty");
        Saved ->
            _ = os:cmd("stty " ++ Saved ++ " </dev/tty >/dev/tty 2>/dev/tty")
    end,
    ok.

install_signal_handler() ->
    %% SIGINT is owned by the runtime and cannot be subscribed to. Ctrl-C is
    %% delivered as a key once the terminal is in raw mode; SIGTERM and SIGHUP
    %% are the signals that would otherwise skip terminal restoration.
    _ = try os:set_signal(sigterm, handle) catch _:_ -> ok end,
    _ = try os:set_signal(sighup, handle) catch _:_ -> ok end,
    _ = gen_event:add_handler(erl_signal_server, ?MODULE, []),
    ok.

init([]) ->
    {ok, []}.

handle_event(sigterm, State) ->
    restore(),
    {ok, State};
handle_event(sighup, State) ->
    restore(),
    {ok, State};
handle_event(_Other, State) ->
    {ok, State}.

handle_call(_Request, State) ->
    {ok, ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_Old, State, _Extra) ->
    {ok, State}.

monotonic_ms() ->
    erlang:monotonic_time(millisecond).

is_darwin() ->
    case os:type() of
        {unix, darwin} -> true;
        _ -> false
    end.

process_count() ->
    erlang:system_info(process_count).
