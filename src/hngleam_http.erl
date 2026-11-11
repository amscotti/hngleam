-module(hngleam_http).
-export([get/2, response/1, decode_chunked/1]).

%% HTTPS GET for the Hacker News endpoints.
%%
%% Each call connects from the calling process. Only what those endpoints need
%% is implemented: GET, no redirects, no compression, HTTP/1.1.
%%
%% The socket is always closed, including when send or recv fails. The read
%% stops at Content-Length or the end of a chunked body, and the whole read
%% shares one deadline so a slow proxy cannot reset the timeout per chunk.

get(Url, Timeout) ->
    try
        do_get(Url, Timeout)
    catch
        _:timeout -> {0, <<"timeout">>};
        _:{connect, Reason} -> {0, transport_reason(<<"connect">>, Reason)};
        _:{recv, Reason} -> {0, transport_reason(<<"receive">>, Reason)};
        _:Reason -> {0, transport_reason(<<"request">>, Reason)}
    end.

%% Pure response parsing, exported for tests.
response(Data) ->
    parse_response(Data).

%% Pure chunked-body decoding, exported for tests.
decode_chunked(Body) ->
    dechunk(Body, <<>>).

do_get(Url, Timeout) ->
    _ = application:ensure_all_started(ssl),
    Uri = uri_string:parse(binary_to_list(Url)),
    Scheme = maps:get(scheme, Uri),
    Host = maps:get(host, Uri),
    Path0 = maps:get(path, Uri, "/"),
    Path = case maps:get(query, Uri, undefined) of
               undefined -> Path0;
               Query -> Path0 ++ "?" ++ Query
           end,
    Port = maps:get(port, Uri, default_port(Scheme)),
    HostHeader = case maps:get(port, Uri, undefined) of
                     undefined -> Host;
                     _ -> Host ++ ":" ++ integer_to_list(Port)
                 end,
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    Socket = connect(Scheme, Host, Port, time_left(Deadline)),
    try
        ok = send(Scheme, Socket, request(Path, HostHeader)),
        Data = recv_message(Scheme, Socket, Deadline, <<>>),
        parse_response(Data)
    after
        close(Scheme, Socket)
    end.

request(Path, HostHeader) ->
    ["GET ", Path, " HTTP/1.1\r\n",
     "Host: ", HostHeader, "\r\n",
     "Accept: application/json\r\n",
     "User-Agent: hngleam/1.0\r\n",
     "Connection: close\r\n\r\n"].

transport_reason(Kind, timeout) ->
    <<Kind/binary, ":timeout">>;
transport_reason(Kind, nxdomain) ->
    <<Kind/binary, ":nxdomain">>;
transport_reason(Kind, econnrefused) ->
    <<Kind/binary, ":econnrefused">>;
transport_reason(Kind, ehostunreach) ->
    <<Kind/binary, ":unreachable">>;
transport_reason(Kind, enetunreach) ->
    <<Kind/binary, ":unreachable">>;
transport_reason(Kind, closed) ->
    <<Kind/binary, ":closed">>;
transport_reason(Kind, Reason) ->
    iolist_to_binary([Kind, ":", io_lib:format("~p", [Reason])]).

default_port("https") -> 443;
default_port(_) -> 80.

time_left(Deadline) ->
    max(0, Deadline - erlang:monotonic_time(millisecond)).

connect("https", Host, Port, Timeout) ->
    Options = [binary,
               {active, false},
               {verify, verify_peer},
               {cacerts, public_key:cacerts_get()},
               {server_name_indication, Host},
               {customize_hostname_check,
                [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]},
               {depth, 4}],
    case ssl:connect(Host, Port, Options, Timeout) of
        {ok, Socket} -> Socket;
        {error, Reason} -> error({connect, Reason})
    end;
connect(_, Host, Port, Timeout) ->
    case gen_tcp:connect(Host, Port, [binary, {active, false}], Timeout) of
        {ok, Socket} -> Socket;
        {error, Reason} -> error({connect, Reason})
    end.

send("https", Socket, Data) -> ssl:send(Socket, Data);
send(_, Socket, Data) -> gen_tcp:send(Socket, Data).

recv("https", Socket, Timeout) -> ssl:recv(Socket, 0, Timeout);
recv(_, Socket, Timeout) -> gen_tcp:recv(Socket, 0, Timeout).

close("https", Socket) ->
    _ = ssl:close(Socket),
    ok;
close(_, Socket) ->
    _ = gen_tcp:close(Socket),
    ok.

%% Read until the body is complete, the peer closes, or the deadline passes.
%% A timeout after a parseable response keeps the bytes already received.
recv_message(Scheme, Socket, Deadline, Acc) ->
    case message_complete(Acc) of
        true -> Acc;
        false ->
            Left = time_left(Deadline),
            case Left =< 0 of
                true -> unfinished(Acc);
                false ->
                    case recv(Scheme, Socket, Left) of
                        {ok, Chunk} ->
                            recv_message(Scheme, Socket, Deadline,
                                         <<Acc/binary, Chunk/binary>>);
                        {error, closed} ->
                            case Acc of
                                <<>> -> error({recv, closed});
                                _ -> Acc
                            end;
                        {error, timeout} -> unfinished(Acc);
                        {error, Reason} -> error({recv, Reason})
                    end
            end
    end.

unfinished(<<>>) ->
    error(timeout);
unfinished(Acc) ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        nomatch -> error(timeout);
        _ -> Acc
    end.

message_complete(Acc) ->
    case split_head(Acc) of
        {ok, Headers, Body} -> body_complete(Headers, Body);
        incomplete -> false
    end.

split_head(Acc) ->
    case binary:split(Acc, <<"\r\n\r\n">>) of
        [Head, Body] -> {ok, header_list(Head), Body};
        _ -> incomplete
    end.

body_complete(Headers, Body) ->
    case lists:keyfind(<<"transfer-encoding">>, 1, Headers) of
        {_, <<"chunked", _/binary>>} -> chunked_done(Body);
        _ ->
            case content_length(Headers) of
                {ok, Len} -> byte_size(Body) >= Len;
                error -> false
            end
    end.

content_length(Headers) ->
    case lists:keyfind(<<"content-length">>, 1, Headers) of
        {_, LenBin} ->
            try binary_to_integer(trim(LenBin)) of
                Len when is_integer(Len), Len >= 0 -> {ok, Len};
                _ -> error
            catch
                _:_ -> error
            end;
        _ -> error
    end.

chunked_done(Body) ->
    case binary:split(Body, <<"\r\n">>) of
        [SizePart, Rest] ->
            case chunk_size(SizePart) of
                {ok, 0} -> true;
                {ok, Size} ->
                    case Rest of
                        <<_:Size/binary, "\r\n", Rest2/binary>> ->
                            chunked_done(Rest2);
                        _ -> false
                    end;
                error -> false
            end;
        _ -> false
    end.

chunk_size(SizePart) ->
    Hex = case binary:split(SizePart, <<";">>) of
              [First | _] -> First
          end,
    try binary_to_integer(trim(Hex), 16) of
        Size when is_integer(Size), Size >= 0 -> {ok, Size};
        _ -> error
    catch
        _:_ -> error
    end.

parse_response(Data) ->
    case split_head(Data) of
        {ok, Headers, Body} ->
            case header_lines(Data) of
                [StatusLine | _] ->
                    case binary:split(StatusLine, <<" ">>, [global]) of
                        [_Version, CodeBin | _] ->
                            Code = binary_to_integer(CodeBin),
                            {Code, decode_body(Headers, Body)};
                        _ ->
                            {0, <<"bad status line">>}
                    end;
                _ ->
                    {0, <<"bad status line">>}
            end;
        incomplete ->
            {0, <<"no response">>}
    end.

header_lines(Data) ->
    case binary:split(Data, <<"\r\n\r\n">>) of
        [Head, _] -> binary:split(Head, <<"\r\n">>, [global]);
        _ -> []
    end.

header_list(Head) ->
    Lines = case binary:split(Head, <<"\r\n">>, [global]) of
                [_Status | Rest] -> Rest;
                _ -> []
            end,
    [parse_header(Line) || Line <- Lines].

decode_body(Headers, Body) ->
    case lists:keyfind(<<"transfer-encoding">>, 1, Headers) of
        {_, <<"chunked", _/binary>>} -> dechunk(Body, <<>>);
        _ ->
            case content_length(Headers) of
                {ok, Len} ->
                    case Body of
                        <<Want:Len/binary, _/binary>> -> Want;
                        _ -> Body
                    end;
                error -> Body
            end
    end.

parse_header(Line) ->
    case binary:split(Line, <<":">>) of
        [Name, Value] -> {lower(Name), trim(Value)};
        _ -> {lower(Line), <<>>}
    end.

lower(Bin) -> list_to_binary(string:lowercase(binary_to_list(Bin))).

trim(Bin) ->
    list_to_binary(string:trim(binary_to_list(Bin))).

dechunk(Bin, Acc) ->
    case binary:split(Bin, <<"\r\n">>) of
        [SizePart, Rest] ->
            case chunk_size(SizePart) of
                {ok, 0} -> Acc;
                {ok, Size} ->
                    case Rest of
                        <<Chunk:Size/binary, "\r\n", Rest2/binary>> ->
                            dechunk(Rest2, <<Acc/binary, Chunk/binary>>);
                        <<Chunk:Size/binary, _/binary>> ->
                            <<Acc/binary, Chunk/binary>>;
                        _ -> Acc
                    end;
                error -> Acc
            end;
        _ -> Acc
    end.
