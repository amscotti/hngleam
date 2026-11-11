//// Comments arrive as a small subset of HTML. This turns that subset into
//// plain text that the layout can wrap.
////
//// A `<` is only a tag when it begins a name (`<p>`, `</li>`, `<!--`).
//// Anything else, including `a < b` and an unclosed `<`, is kept as text.
//// Whitespace inside `<pre>` is preserved; everywhere else it is collapsed.

import gleam/int
import gleam/list
import gleam/string
import hngleam/text/sanitize

/// Convert a comment body from HTML to readable plain text.
pub fn to_text(html: String) -> String {
  html
  |> string.replace("\r\n", "\n")
  |> string.replace("\r", "\n")
  |> string.to_graphemes()
  |> parse(False, "", [])
  |> render
  |> sanitize.clean
}

/// Decode HTML entities, leaving tags untouched. Titles use this: they are
/// entity-encoded plain text, not markup.
pub fn decode_entities(text: String) -> String {
  text
  |> string.to_graphemes()
  |> decode_chars("")
  |> sanitize.clean
}

type Piece {
  Flow(String)
  Code(String)
}

fn parse(
  chars: List(String),
  in_code: Bool,
  acc: String,
  pieces: List(Piece),
) -> List(Piece) {
  case chars {
    [] -> finish(in_code, acc, pieces)
    ["<", ..rest] ->
      case read_tag(rest) {
        Ok(#(raw, remaining)) -> {
          let #(next_code, text) = tag_effect(raw, in_code)
          case in_code == next_code {
            True -> parse(remaining, in_code, acc <> text, pieces)
            False ->
              parse(remaining, next_code, text, push(pieces, in_code, acc))
          }
        }
        Error(remaining) -> parse(remaining, in_code, acc <> "<", pieces)
      }
    ["&", ..rest] ->
      case entity(rest) {
        Ok(#(text, remaining)) -> parse(remaining, in_code, acc <> text, pieces)
        Error(_) -> parse(rest, in_code, acc <> "&", pieces)
      }
    ["\t", ..rest] -> {
      let spaces = case in_code {
        True -> "  "
        False -> " "
      }
      parse(rest, in_code, acc <> spaces, pieces)
    }
    [char, ..rest] -> parse(rest, in_code, acc <> char, pieces)
  }
}

fn decode_chars(chars: List(String), acc: String) -> String {
  case chars {
    [] -> acc
    ["&", ..rest] ->
      case entity(rest) {
        Ok(#(text, remaining)) -> decode_chars(remaining, acc <> text)
        Error(_) -> decode_chars(rest, acc <> "&")
      }
    [char, ..rest] -> decode_chars(rest, acc <> char)
  }
}

/// `Ok` is a closed tag and the characters after its `>`. `Error` means this
/// `<` was not a tag, and parsing should continue with the returned characters.
fn read_tag(
  chars: List(String),
) -> Result(#(String, List(String)), List(String)) {
  case chars {
    [] -> Error([])
    [first, ..] ->
      case tag_start(first) {
        False -> Error(chars)
        True ->
          case take_until(chars, ">") {
            Ok(#(tag, remaining)) -> Ok(#(tag, remaining))
            Error(_) -> Error(chars)
          }
      }
  }
}

fn tag_start(char: String) -> Bool {
  char == "/" || char == "!" || is_name_char(char)
}

fn take_until(
  chars: List(String),
  terminator: String,
) -> Result(#(String, List(String)), Nil) {
  take_until_acc(chars, terminator, "")
}

fn take_until_acc(
  chars: List(String),
  terminator: String,
  acc: String,
) -> Result(#(String, List(String)), Nil) {
  case chars {
    [] -> Error(Nil)
    [char, ..rest] ->
      case char == terminator {
        True -> Ok(#(acc, rest))
        False -> take_until_acc(rest, terminator, acc <> char)
      }
  }
}

/// The tag's replacement text, and whether the following characters are code.
fn tag_effect(raw: String, in_code: Bool) -> #(Bool, String) {
  let #(closing, name) = tag_name(raw)
  case name, closing, in_code {
    "pre", False, False -> #(True, "\n")
    "pre", False, True -> #(True, "")
    "pre", True, True -> #(False, "\n")
    "pre", True, False -> #(False, "")
    _, _, True -> #(True, case name {
      "br" -> "\n"
      _ -> ""
    })
    "p", _, False -> #(False, "\n\n")
    "br", _, False -> #(False, "\n")
    "li", False, False -> #(False, "\n• ")
    "div", _, False -> #(False, "\n")
    "blockquote", _, False -> #(False, "\n")
    _, _, False -> #(False, "")
  }
}

/// `(closing, name)` for a raw tag, ignoring attributes. `<p class="x">` and
/// `<br/>` both yield a bare name, so `<picture>` is not treated as `<p>`.
fn tag_name(raw: String) -> #(Bool, String) {
  let chars = string.to_graphemes(string.trim(raw))
  let #(closing, chars) = case chars {
    ["/", ..rest] -> #(True, rest)
    _ -> #(False, chars)
  }
  #(closing, read_name(chars, ""))
}

fn read_name(chars: List(String), acc: String) -> String {
  case chars {
    [char, ..rest] ->
      case is_name_char(char) {
        True -> read_name(rest, acc <> string.lowercase(char))
        False -> acc
      }
    [] -> acc
  }
}

fn is_name_char(char: String) -> Bool {
  string.length(char) == 1
  && string.contains(
    "abcdefghijklmnopqrstuvwxyz0123456789",
    string.lowercase(char),
  )
}

const entities = [
  #("amp;", "&"),
  #("lt;", "<"),
  #("gt;", ">"),
  #("quot;", "\""),
  #("apos;", "'"),
  #("nbsp;", " "),
  #("#x27;", "'"),
  #("#X27;", "'"),
  #("#x2F;", "/"),
  #("#x2f;", "/"),
  #("#39;", "'"),
  #("#47;", "/"),
  #("#34;", "\""),
  #("#x3D;", "="),
  #("#x3d;", "="),
  #("#x60;", "`"),
]

fn entity(chars: List(String)) -> Result(#(String, List(String)), Nil) {
  case
    list.find(entities, fn(pair) {
      has_prefix(chars, string.to_graphemes(pair.0))
    })
  {
    Ok(#(name, replacement)) ->
      Ok(#(replacement, drop(chars, string.length(name))))
    Error(_) -> numeric_entity(chars)
  }
}

fn numeric_entity(chars: List(String)) -> Result(#(String, List(String)), Nil) {
  case chars {
    ["#", "x", ..rest] -> read_digits(rest, "", 16)
    ["#", "X", ..rest] -> read_digits(rest, "", 16)
    ["#", ..rest] -> read_digits(rest, "", 10)
    _ -> Error(Nil)
  }
}

fn read_digits(
  chars: List(String),
  acc: String,
  base: Int,
) -> Result(#(String, List(String)), Nil) {
  case chars {
    [";", ..rest] -> codepoint(acc, base, rest)
    [char, ..rest] ->
      case digit(char, base) {
        True -> read_digits(rest, acc <> char, base)
        False -> Error(Nil)
      }
    [] -> Error(Nil)
  }
}

fn digit(char: String, base: Int) -> Bool {
  case base {
    16 ->
      string.contains("0123456789abcdefABCDEF", char)
      && string.length(char) == 1
    _ -> string.contains("0123456789", char) && string.length(char) == 1
  }
}

fn codepoint(
  digits: String,
  base: Int,
  rest: List(String),
) -> Result(#(String, List(String)), Nil) {
  case digits == "" {
    True -> Error(Nil)
    False ->
      case int.base_parse(digits, base) {
        Error(_) -> Error(Nil)
        Ok(value) ->
          case string.utf_codepoint(value) {
            Error(_) -> Error(Nil)
            Ok(point) -> Ok(#(string.from_utf_codepoints([point]), rest))
          }
      }
  }
}

fn has_prefix(chars: List(String), prefix: List(String)) -> Bool {
  case chars, prefix {
    _, [] -> True
    [], _ -> False
    [left, ..lefts], [right, ..rights] ->
      case left == right {
        True -> has_prefix(lefts, rights)
        False -> False
      }
  }
}

fn drop(chars: List(String), count: Int) -> List(String) {
  case count <= 0 {
    True -> chars
    False ->
      case chars {
        [] -> []
        [_, ..rest] -> drop(rest, count - 1)
      }
  }
}

fn finish(in_code: Bool, acc: String, pieces: List(Piece)) -> List(Piece) {
  list.reverse(push(pieces, in_code, acc))
}

fn push(pieces: List(Piece), in_code: Bool, acc: String) -> List(Piece) {
  case acc {
    "" -> pieces
    _ -> {
      let piece = case in_code {
        True -> Code(acc)
        False -> Flow(acc)
      }
      [piece, ..pieces]
    }
  }
}

fn render(pieces: List(Piece)) -> String {
  pieces
  |> list.map(normalise_piece)
  |> string.join("")
  |> trim_newline_edges
}

fn normalise_piece(piece: Piece) -> String {
  case piece {
    Flow(text) ->
      text
      |> string.split("\n")
      |> list.map(fn(line) { line |> collapse_spaces() |> string.trim_end() })
      |> string.join("\n")
      |> collapse_blank_lines()
    Code(text) -> text |> drop_one_edge_newline()
  }
}

fn drop_one_edge_newline(text: String) -> String {
  let text = case string.starts_with(text, "\n") {
    True -> string.drop_start(text, 1)
    False -> text
  }
  case string.ends_with(text, "\n") {
    True -> string.drop_end(text, 1)
    False -> text
  }
}

fn trim_newline_edges(text: String) -> String {
  text
  |> string.split("\n")
  |> drop_empty_ends()
  |> string.join("\n")
}

fn drop_empty_ends(lines: List(String)) -> List(String) {
  lines
  |> drop_leading_empty()
  |> list.reverse()
  |> drop_leading_empty()
  |> list.reverse()
}

fn drop_leading_empty(lines: List(String)) -> List(String) {
  case lines {
    ["", ..rest] -> drop_leading_empty(rest)
    _ -> lines
  }
}

fn collapse_spaces(line: String) -> String {
  line
  |> string.split(" ")
  |> list.filter(fn(part) { part != "" })
  |> string.join(" ")
}

fn collapse_blank_lines(text: String) -> String {
  let once = string.replace(text, "\n\n\n", "\n\n")
  case once == text {
    True -> text
    False -> collapse_blank_lines(once)
  }
}
