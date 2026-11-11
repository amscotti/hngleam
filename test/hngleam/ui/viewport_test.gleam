import gleeunit/should
import hngleam/ui/viewport

pub fn everything_fits_when_there_is_room_test() {
  viewport.window([1, 1, 1], 0, 10) |> should.equal(#(0, 3))
}

pub fn selection_at_the_top_scrolls_down_only_test() {
  viewport.window([1, 1, 1, 1, 1], 0, 2) |> should.equal(#(0, 2))
}

pub fn selection_in_the_middle_keeps_context_above_test() {
  // Three rows are available: one above the selection, the selection, one below.
  viewport.window([1, 1, 1, 1, 1, 1, 1], 3, 3) |> should.equal(#(1, 4))
}

pub fn selection_at_the_bottom_scrolls_up_test() {
  viewport.window([1, 1, 1, 1, 1], 4, 2) |> should.equal(#(3, 5))
}

pub fn rows_of_different_heights_are_respected_test() {
  // A five row item does not fit in three rows on its own, so only it shows.
  viewport.window([1, 5, 1], 1, 3) |> should.equal(#(1, 2))
}

pub fn a_window_shorter_than_one_row_still_shows_the_selection_test() {
  viewport.window([3, 3], 1, 1) |> should.equal(#(1, 2))
}

pub fn empty_lists_have_an_empty_window_test() {
  viewport.window([], 0, 5) |> should.equal(#(0, 0))
}
