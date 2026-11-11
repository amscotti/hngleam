//// Wrapping and truncation measured in terminal columns.
////
//// The layout measures text before it is drawn, and the UI renders those
//// lines as they are. Width is display columns: a CJK character or emoji
//// counts as two, and a combining mark counts as zero.

import gleam/list
import gleam/string
import hngleam/text/width.{columns, grapheme_width}

/// Wrap text into lines no wider than `width` columns. Existing newlines
/// start a new paragraph and words longer than `width` are split.
pub fn wrap(text: String, width: Int) -> List(String) {
  case width < 1 {
    True -> [text]
    False ->
      text
      |> string.split("\n")
      |> list.map(wrap_paragraph(_, width))
      |> list.flatten()
  }
}

/// Cut text to at most `width` columns, marking the cut with an ellipsis.
pub fn truncate(text: String, width width: Int) -> String {
  case width < 1 {
    True -> ""
    False ->
      case columns(text) <= width {
        True -> text
        False ->
          case width == 1 {
            True -> "…"
            False -> take_columns(text, width - 1).0 <> "…"
          }
      }
  }
}

/// Truncate or pad text so that it is exactly `width` columns wide.
pub fn fit(text: String, width width: Int) -> String {
  let width = case width < 0 {
    True -> 0
    False -> width
  }
  let text = truncate(text, width)
  text <> string.repeat(" ", width - columns(text))
}

/// Pad text on the left with spaces so that it is `width` columns wide.
pub fn pad_left(text: String, width width: Int) -> String {
  let padding = width - columns(text)
  case padding > 0 {
    True -> string.repeat(" ", padding) <> text
    False -> text
  }
}

fn wrap_paragraph(paragraph: String, width: Int) -> List(String) {
  let words =
    paragraph
    |> string.split(" ")
    |> list.filter(fn(word) { word != "" })

  case words {
    [] -> [""]
    _ -> wrap_words(words, width, "", [])
  }
}

fn wrap_words(
  words: List(String),
  width: Int,
  line: String,
  lines: List(String),
) -> List(String) {
  case words {
    [] -> list.reverse([line, ..lines])
    [word, ..rest] ->
      case columns(word) <= width {
        True -> {
          let candidate = case line {
            "" -> word
            _ -> line <> " " <> word
          }
          case columns(candidate) <= width {
            True -> wrap_words(rest, width, candidate, lines)
            False -> wrap_words(rest, width, word, [line, ..lines])
          }
        }
        False -> {
          let lines = case line {
            "" -> lines
            _ -> [line, ..lines]
          }
          let #(complete, tail) = hard_split(word, width)
          wrap_words(
            rest,
            width,
            tail,
            list.append(list.reverse(complete), lines),
          )
        }
      }
  }
}

/// Split a word into full-width chunks plus the remainder that still fits on
/// the current line. Splits fall on grapheme boundaries and never past the
/// column budget, so a double-width character is not cut in half.
fn hard_split(word: String, width: Int) -> #(List(String), String) {
  case columns(word) <= width {
    True -> #([], word)
    False -> {
      let #(head, rest) = take_columns(word, width)
      let #(complete, tail) = hard_split(rest, width)
      #([head, ..complete], tail)
    }
  }
}

/// The longest prefix of `text` that fits in `columns`, and the remainder.
fn take_columns(text: String, columns: Int) -> #(String, String) {
  take_columns_loop(string.to_graphemes(text), columns, "")
}

fn take_columns_loop(
  graphemes: List(String),
  remaining: Int,
  acc: String,
) -> #(String, String) {
  case graphemes {
    [] -> #(acc, "")
    [grapheme, ..rest] -> {
      let needed = grapheme_width(grapheme)
      case needed <= remaining {
        True -> take_columns_loop(rest, remaining - needed, acc <> grapheme)
        False -> #(acc, string.concat([grapheme, ..rest]))
      }
    }
  }
}
