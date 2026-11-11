//// Terminal column widths.
////
//// `string.length` counts graphemes. A terminal counts columns: most emoji
//// and East Asian characters take two, and combining marks and format
//// characters take none. The layout uses this module so a wide character
//// cannot push a box border out of line.

import gleam/list
import gleam/string

/// How many columns `text` occupies.
pub fn columns(text: String) -> Int {
  text
  |> string.to_graphemes()
  |> list.fold(0, fn(total, grapheme) { total + grapheme_width(grapheme) })
}

/// Columns occupied by one extended grapheme cluster.
pub fn grapheme_width(grapheme: String) -> Int {
  let points =
    grapheme
    |> string.to_utf_codepoints()
    |> list.map(string.utf_codepoint_to_int)

  case points {
    [] -> 0
    _ ->
      case list.all(points, zero_width) {
        True -> 0
        False ->
          case list.any(points, wide) {
            True -> 2
            False -> 1
          }
      }
  }
}

fn zero_width(code: Int) -> Bool {
  case code {
    code if code >= 0x0300 && code <= 0x036f -> True
    code if code >= 0x0483 && code <= 0x0489 -> True
    code if code >= 0x0591 && code <= 0x05bd -> True
    code if code == 0x05bf || code == 0x05c1 || code == 0x05c2 -> True
    code if code == 0x05c4 || code == 0x05c5 || code == 0x05c7 -> True
    code if code >= 0x0610 && code <= 0x061a -> True
    code if code >= 0x064b && code <= 0x065f -> True
    code if code == 0x0670 -> True
    code if code >= 0x06d6 && code <= 0x06dc -> True
    code if code >= 0x06df && code <= 0x06e4 -> True
    code if code >= 0x06e7 && code <= 0x06e8 -> True
    code if code >= 0x06ea && code <= 0x06ed -> True
    code if code == 0x0711 -> True
    code if code >= 0x0730 && code <= 0x074a -> True
    code if code >= 0x07a6 && code <= 0x07b0 -> True
    code if code >= 0x07eb && code <= 0x07f3 -> True
    code if code >= 0x0816 && code <= 0x0819 -> True
    code if code >= 0x081b && code <= 0x0823 -> True
    code if code >= 0x0825 && code <= 0x0827 -> True
    code if code >= 0x0829 && code <= 0x082d -> True
    code if code >= 0x0859 && code <= 0x085b -> True
    code if code == 0x200b || code == 0x200c || code == 0x200d -> True
    code if code == 0x200e || code == 0x200f || code == 0xfeff -> True
    code if code >= 0x202a && code <= 0x202e -> True
    code if code >= 0x2060 && code <= 0x2064 -> True
    code if code >= 0x2066 && code <= 0x206f -> True
    code if code >= 0x20d0 && code <= 0x20ff -> True
    code if code >= 0xfe00 && code <= 0xfe0f -> True
    code if code >= 0xfe20 && code <= 0xfe2f -> True
    code if code >= 0xe0100 && code <= 0xe01ef -> True
    _ -> False
  }
}

/// Wide and fullwidth characters, plus emoji that terminals draw in two columns.
/// Ambiguous-width characters stay one column, which matches a Western locale.
fn wide(code: Int) -> Bool {
  case code {
    code if code >= 0x1100 && code <= 0x115f -> True
    code if code == 0x2329 || code == 0x232a -> True
    code if code >= 0x2e80 && code <= 0xa4cf -> True
    code if code >= 0xac00 && code <= 0xd7a3 -> True
    code if code >= 0xf900 && code <= 0xfaff -> True
    code if code >= 0xfe10 && code <= 0xfe19 -> True
    code if code >= 0xfe30 && code <= 0xfe6f -> True
    code if code >= 0xff00 && code <= 0xff60 -> True
    code if code >= 0xffe0 && code <= 0xffe6 -> True
    code if code >= 0x1f300 && code <= 0x1f64f -> True
    code if code >= 0x1f680 && code <= 0x1f6ff -> True
    code if code >= 0x1f900 && code <= 0x1f9ff -> True
    code if code >= 0x1fa00 && code <= 0x1faff -> True
    code if code >= 0x20000 && code <= 0x3fffd -> True
    _ -> False
  }
}
