import gleam/dynamic/decode.{DecodeError}
import gleam/list
import gleam/string
import gleeunit/should
import hngleam/app/error

pub fn network_errors_are_described_test() {
  error.Network(reason: "connection refused")
  |> error.describe()
  |> string.contains("connection refused")
  |> should.be_true()
}

pub fn timeouts_are_described_test() {
  error.Timeout
  |> error.describe()
  |> string.contains("timed out")
  |> should.be_true()
}

pub fn status_errors_name_the_endpoint_test() {
  let text =
    error.describe(error.HttpStatus(code: 500, endpoint: "the Top feed"))
  text |> string.contains("the Top feed") |> should.be_true()
  text |> string.contains("500") |> should.be_true()
}

pub fn decode_errors_count_the_problems_test() {
  let text =
    error.describe(
      error.Decode(endpoint: "search results", errors: [
        DecodeError(expected: "String", found: "Int", path: []),
      ]),
    )
  text |> string.contains("search results") |> should.be_true()
  text |> string.contains("1 decoding error") |> should.be_true()
}

pub fn browser_errors_name_the_command_test() {
  error.BrowserUnavailable(command: "xdg-open")
  |> error.describe()
  |> string.contains("xdg-open")
  |> should.be_true()
}

pub fn retry_hint_is_appended_test() {
  error.Timeout
  |> error.describe_with_retry()
  |> string.contains("Press r to retry")
  |> should.be_true()
}

pub fn transport_tokens_become_short_errors_test() {
  error.from_transport("timeout") |> should.equal(error.Timeout)
  error.from_transport("connect:timeout") |> should.equal(error.Timeout)
  error.from_transport("connect:nxdomain")
  |> should.equal(error.Network(reason: "the host could not be found"))
  error.from_transport("connect:econnrefused")
  |> should.equal(error.Network(reason: "the connection was refused"))
  error.from_transport("receive:closed")
  |> should.equal(error.Network(reason: "the connection closed"))

  let long = string.repeat("x", 200)
  case error.from_transport(long) {
    error.Network(reason:) -> {
      string.length(reason) |> should.equal(120)
      string.ends_with(reason, "...") |> should.be_true()
    }
    _ -> panic as "expected a network error"
  }
}

pub fn every_variant_has_a_description_test() {
  [
    error.Network(reason: "x"),
    error.Timeout,
    error.HttpStatus(code: 404, endpoint: "y"),
    error.Decode(endpoint: "z", errors: []),
    error.BrowserUnavailable(command: "open"),
  ]
  |> list.each(fn(problem) { error.describe(problem) |> should.not_equal("") })
}
