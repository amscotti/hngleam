//// The scrolling window used by every list: given the height of each item, the
//// selected index and the number of rows available, decide which items are
//// drawn.
////
//// The rules: the selection is always visible, the window grows upwards from
//// the selection first (so context above the cursor is kept), then downwards.
//// An item taller than the whole viewport is shown from its top.

import gleam/int
import gleam/list
import gleam/option

/// The half-open range of item indices to draw.
pub fn window(
  heights: List(Int),
  selected: Int,
  available: Int,
) -> #(Int, Int) {
  let count = list.length(heights)
  let total = list.fold(heights, 0, int.add)

  case count == 0 || total <= available {
    True -> #(0, count)
    False -> {
      let available = int.max(available, 1)
      let selected = int.clamp(selected, 0, count - 1)
      let selected_height = at(heights, selected) |> option.unwrap(1)
      let used = int.min(selected_height, available)

      let #(start, used) = grow_up(heights, selected, used, available)
      let end = grow_down(heights, selected + 1, used, available)
      #(start, end)
    }
  }
}

fn grow_up(
  heights: List(Int),
  index: Int,
  used: Int,
  available: Int,
) -> #(Int, Int) {
  case index <= 0 {
    True -> #(index, used)
    False -> {
      let previous = at(heights, index - 1) |> option.unwrap(1)
      case used + previous <= available {
        True -> grow_up(heights, index - 1, used + previous, available)
        False -> #(index, used)
      }
    }
  }
}

fn grow_down(heights: List(Int), index: Int, used: Int, available: Int) -> Int {
  case at(heights, index) {
    option.None -> index
    option.Some(height) ->
      case used + height <= available {
        True -> grow_down(heights, index + 1, used + height, available)
        False -> index
      }
  }
}

fn at(items: List(a), index: Int) -> option.Option(a) {
  case index < 0 {
    True -> option.None
    False -> list.drop(items, index) |> list.first |> option.from_result
  }
}
