import gleeunit/should

@external(erlang, "hngleam_http", "response")
fn response(data: String) -> #(Int, String)

@external(erlang, "hngleam_http", "decode_chunked")
fn decode_chunked(body: String) -> String

pub fn content_length_trims_bytes_past_the_body_test() {
  response("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhelloEXTRA")
  |> should.equal(#(200, "hello"))
}

pub fn chunk_extensions_are_stripped_before_the_size_test() {
  decode_chunked("1a;ext=val\r\nabcdefghijklmnopqrstuvwxyz\r\n0\r\n\r\n")
  |> should.equal("abcdefghijklmnopqrstuvwxyz")
}

pub fn a_chunked_response_joins_its_chunks_test() {
  response(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n",
  )
  |> should.equal(#(200, "hello"))
}
