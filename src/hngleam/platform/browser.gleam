//// Opening a URL in the user's browser.
////
//// Only `http` and `https` links are opened. Anything else — `file:`,
//// `javascript:`, or a value that starts with `-` — is refused, because the
//// system opener would treat it as a program or as its own command-line flag.
//// The URL is passed after `--` so the opener cannot parse it as an option.
//// macOS prefers `open`, even when Homebrew has also installed `xdg-open`.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import hngleam/app/error.{type AppError, BrowserUnavailable}
import shellout

/// Open a URL in the system browser, without blocking the UI (the caller runs
/// this inside a command process).
pub fn open(url: String) -> Result(Nil, AppError) {
  use url <- result.try(web_url(url))
  case opener() {
    Error(_) -> Error(BrowserUnavailable(command: "xdg-open or open"))
    Ok(executable) ->
      case
        shellout.command(run: executable, with: ["--", url], in: ".", opt: [])
      {
        Ok(_) -> Ok(Nil)
        Error(#(code, _output)) ->
          Error(BrowserUnavailable(
            command: executable <> " exited " <> int.to_string(code),
          ))
      }
  }
}

/// Accept a URL only when it is an absolute http(s) link with no control
/// characters or whitespace.
pub fn web_url(url: String) -> Result(String, AppError) {
  let lower = string.lowercase(url)
  let scheme_ok =
    string.starts_with(lower, "https://")
    || string.starts_with(lower, "http://")
  case scheme_ok && !has_control_or_space(url) && string.length(url) > 8 {
    True -> Ok(url)
    False ->
      Error(BrowserUnavailable(
        command: "only http and https links can be opened",
      ))
  }
}

/// The command that opens URLs on this machine.
pub fn opener() -> Result(String, Nil) {
  choose_opener(
    on_darwin: is_darwin(),
    xdg: which("xdg-open"),
    open: which("open"),
  )
}

/// Pick an opener. Darwin tries `open` first so a Homebrew `xdg-open` does
/// not shadow it.
pub fn choose_opener(
  on_darwin on_darwin: Bool,
  xdg xdg: Result(String, Nil),
  open open_cmd: Result(String, Nil),
) -> Result(String, Nil) {
  case on_darwin {
    True -> first(open_cmd, xdg)
    False -> first(xdg, open_cmd)
  }
}

fn first(
  preferred: Result(String, Nil),
  fallback: Result(String, Nil),
) -> Result(String, Nil) {
  case preferred {
    Ok(path) -> Ok(path)
    Error(_) -> fallback
  }
}

fn has_control_or_space(url: String) -> Bool {
  url
  |> string.to_utf_codepoints
  |> list.any(fn(point) {
    let code = string.utf_codepoint_to_int(point)
    code <= 32 || code == 127
  })
}

fn which(name: String) -> Result(String, Nil) {
  shellout.which(name)
  |> result.replace_error(Nil)
}

@external(erlang, "hngleam_ffi", "is_darwin")
fn is_darwin() -> Bool
