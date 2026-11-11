import gleam/option
import gleeunit/should
import hngleam/domain/listing

pub fn empty_list_has_no_selection_test() {
  let items = listing.from_list([])
  listing.is_empty(items) |> should.be_true()
  listing.current(items) |> should.equal(option.None)
  listing.index(items) |> should.equal(option.None)
  listing.length(items) |> should.equal(0)
}

pub fn selection_clamps_at_both_ends_test() {
  let items = listing.from_list([10, 20, 30])
  items
  |> listing.previous()
  |> listing.current()
  |> should.equal(option.Some(10))
  items
  |> listing.next()
  |> listing.next()
  |> listing.next()
  |> listing.current()
  |> should.equal(option.Some(30))
}

pub fn indexed_pairs_items_with_positions_test() {
  listing.from_list(["a", "b"])
  |> listing.indexed()
  |> should.equal([#(0, "a"), #(1, "b")])
}

pub fn to_list_round_trips_test() {
  listing.from_list([1, 2, 3]) |> listing.to_list() |> should.equal([1, 2, 3])
}
