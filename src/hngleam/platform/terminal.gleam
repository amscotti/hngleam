//// Reading the terminal's dimensions, and restoring it if the UI ever dies
//// without cleaning up.
////
//// `io:columns/0` and `io:rows/0` return `{error, enotsup}` when stdout is not
//// a terminal, which is how the entry point detects that it has no business
//// drawing a UI.

import gleam/option.{type Option, Some}
import hngleam/domain/terminal_size.{type TerminalSize}

@external(erlang, "hngleam_ffi", "columns")
fn erl_columns() -> Option(Int)

@external(erlang, "hngleam_ffi", "rows")
fn erl_rows() -> Option(Int)

/// The current terminal size, or `Error(Nil)` when there is no terminal.
pub fn size() -> Result(TerminalSize, Nil) {
  case erl_columns(), erl_rows() {
    Some(width), Some(height) -> Ok(terminal_size.make(width, height))
    _, _ -> Error(Nil)
  }
}

/// True when the process is attached to a terminal.
pub fn attached() -> Bool {
  case size() {
    Ok(_) -> True
    Error(_) -> False
  }
}

/// Remember the current terminal settings and arrange for them to be restored
/// if the runtime receives SIGTERM or SIGHUP.
pub fn prepare() -> Nil {
  erl_prepare()
}

/// Show the cursor, leave the alternate screen, and restore the terminal
/// driver. Used when the UI process dies without restoring the terminal itself.
pub fn restore() -> Nil {
  erl_restore()
}

@external(erlang, "hngleam_ffi", "prepare")
fn erl_prepare() -> Nil

@external(erlang, "hngleam_ffi", "restore")
fn erl_restore() -> Nil
