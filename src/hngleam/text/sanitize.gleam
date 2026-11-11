//// Strip terminal control sequences from text that came from the network.
////
//// Story titles, author names, URLs and comment bodies are untrusted. An
//// escape sequence in any of them can retitle the terminal, clear the screen
//// or leave the emulator's parser mid-sequence after a wrap or truncation.

import gleam/string

/// Remove ANSI escape sequences and non-printable control characters.
/// Newlines and tabs are kept; the layout decides what to do with them.
pub fn clean(text: String) -> String {
  text
  |> string.to_graphemes()
  |> drop_controls("")
}

fn drop_controls(chars: List(String), acc: String) -> String {
  case chars {
    [] -> acc
    ["\u{001b}", ..rest] -> drop_controls(skip_escape(rest), acc)
    ["\u{009b}", ..rest] -> drop_controls(skip_csi(rest), acc)
    [char, ..rest] ->
      case printable(char) {
        True -> drop_controls(rest, acc <> char)
        False -> drop_controls(rest, acc)
      }
  }
}

/// ESC introduces a control sequence. CSI and OSC run until their terminator;
/// every other sequence is ESC plus one character.
fn skip_escape(chars: List(String)) -> List(String) {
  case chars {
    [] -> []
    ["[", ..rest] -> skip_csi(rest)
    ["]", ..rest] -> skip_osc(rest)
    [_, ..rest] -> rest
  }
}

/// CSI runs until a final byte in the range `@`–`~`.
fn skip_csi(chars: List(String)) -> List(String) {
  case chars {
    [] -> []
    [char, ..rest] ->
      case csi_final(char) {
        True -> rest
        False -> skip_csi(rest)
      }
  }
}

/// OSC runs until BEL, or until the two-character ST (`ESC \`).
fn skip_osc(chars: List(String)) -> List(String) {
  case chars {
    [] -> []
    ["\u{0007}", ..rest] -> rest
    ["\u{001b}", "\\", ..rest] -> rest
    ["\u{001b}", ..rest] -> rest
    [_, ..rest] -> skip_osc(rest)
  }
}

fn csi_final(char: String) -> Bool {
  case codepoint(char) {
    n if n >= 0x40 && n <= 0x7e -> True
    _ -> False
  }
}

/// Keep newlines, tabs and every non-control scalar. A grapheme made of
/// several scalars (an emoji, a combining sequence) is kept when none of its
/// scalars is a control character.
fn printable(char: String) -> Bool {
  char
  |> string.to_utf_codepoints()
  |> keeps_every()
}

fn keeps_every(points: List(UtfCodepoint)) -> Bool {
  case points {
    [] -> False
    [point, ..rest] ->
      case keep_scalar(string.utf_codepoint_to_int(point)) {
        False -> False
        True ->
          case rest {
            [] -> True
            _ -> keeps_every(rest)
          }
      }
  }
}

fn keep_scalar(code: Int) -> Bool {
  code == 9 || code == 10 || code >= 32 && code != 127
}

fn codepoint(char: String) -> Int {
  case string.to_utf_codepoints(char) {
    [point] -> string.utf_codepoint_to_int(point)
    _ -> 0
  }
}
