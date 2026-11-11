//// Every way the application can fail, and how each failure is described to
//// the person using it.

import gleam/dynamic/decode.{type DecodeError}
import gleam/int
import gleam/string

/// A failure the user can see and recover from. Nothing in the application
/// panics or swallows an error.
pub type AppError {
  /// The request could not be made at all, e.g. DNS or connection failure.
  Network(reason: String)
  /// The request was made but no response arrived in time.
  Timeout
  /// The server answered with a non-success status.
  HttpStatus(code: Int, endpoint: String)
  /// The response was not the shape we expected.
  Decode(endpoint: String, errors: List(DecodeError))
  /// The browser could not be launched.
  BrowserUnavailable(command: String)
}

/// One short line describing the failure, suitable for the content area.
pub fn describe(error: AppError) -> String {
  case error {
    Network(reason) -> "Couldn't reach Hacker News (" <> reason <> ")"
    Timeout -> "Couldn't reach Hacker News (request timed out)"
    HttpStatus(code:, endpoint:) ->
      "Couldn't load " <> endpoint <> " (HTTP " <> int.to_string(code) <> ")"
    Decode(endpoint:, errors:) ->
      "Couldn't read the response from "
      <> endpoint
      <> " ("
      <> int.to_string(error_count(errors))
      <> " decoding "
      <> plural(errors, "error", "errors")
      <> ")"
    BrowserUnavailable(command:) ->
      "Couldn't open the browser (" <> command <> ")"
  }
}

/// The same line, plus the way out.
pub fn describe_with_retry(error: AppError) -> String {
  describe(error) <> ". Press r to retry."
}

/// A transport failure reported by the HTTP client. The client sends a short
/// token, never a stack trace.
pub fn from_transport(reason: String) -> AppError {
  case reason {
    "timeout" | "connect:timeout" | "receive:timeout" -> Timeout
    "connect:nxdomain" -> Network(reason: "the host could not be found")
    "connect:econnrefused" -> Network(reason: "the connection was refused")
    "connect:unreachable" | "receive:unreachable" ->
      Network(reason: "the network is unreachable")
    "connect:closed" | "receive:closed" ->
      Network(reason: "the connection closed")
    other -> Network(reason: clip(other))
  }
}

fn clip(reason: String) -> String {
  case string.length(reason) > 120 {
    True -> string.slice(reason, 0, 117) <> "..."
    False -> reason
  }
}

fn error_count(errors: List(DecodeError)) -> Int {
  errors |> length()
}

fn plural(errors: List(DecodeError), one: String, many: String) -> String {
  case error_count(errors) == 1 {
    True -> one
    False -> many
  }
}

fn length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + length(rest)
  }
}
