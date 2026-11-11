import gleeunit/should
import hngleam/domain/item_id

pub fn positive_ids_are_accepted_test() {
  item_id.item_id(1) |> result_unwrap() |> item_id.to_int() |> should.equal(1)
  item_id.item_id(42) |> result_unwrap() |> item_id.to_int() |> should.equal(42)
}

pub fn zero_is_rejected_test() {
  item_id.item_id(0) |> should.be_error()
}

pub fn negative_ids_are_rejected_test() {
  item_id.item_id(-5) |> should.be_error()
}

pub fn strings_round_trip_test() {
  item_id.item_id_from_string("50452455")
  |> result_unwrap()
  |> item_id.to_int()
  |> should.equal(50_452_455)
}

pub fn non_numeric_strings_are_rejected_test() {
  item_id.item_id_from_string("abc") |> should.be_error()
  item_id.item_id_from_string("") |> should.be_error()
  item_id.item_id_from_string("  ") |> should.be_error()
}

pub fn hn_url_points_at_the_item_test() {
  item_id.item_id(7)
  |> result_unwrap()
  |> item_id.hn_url()
  |> should.equal("https://news.ycombinator.com/item?id=7")
}

fn result_unwrap(result: Result(a, Nil)) -> a {
  case result {
    Ok(value) -> value
    Error(_) -> panic as "expected Ok"
  }
}
