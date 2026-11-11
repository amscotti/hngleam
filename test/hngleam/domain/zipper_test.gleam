import gleeunit/should
import hngleam/domain/zipper

pub fn empty_lists_are_rejected_test() {
  zipper.from_list([]) |> should.be_error()
}

pub fn current_is_always_a_value_test() {
  zipper.from_list([1, 2, 3])
  |> result_unwrap()
  |> zipper.current()
  |> should.equal(1)
}

pub fn up_at_the_top_stays_put_test() {
  let zipper = zipper.from_list([1, 2, 3]) |> result_unwrap()
  zipper |> zipper.up() |> zipper.current() |> should.equal(1)
  zipper |> zipper.up() |> zipper.index() |> should.equal(0)
}

pub fn down_at_the_bottom_stays_put_test() {
  let zipper =
    zipper.from_list([1, 2, 3])
    |> result_unwrap()
    |> zipper.down()
    |> zipper.down()
    |> zipper.down()
  zipper |> zipper.current() |> should.equal(3)
  zipper |> zipper.index() |> should.equal(2)
  zipper |> zipper.length() |> should.equal(3)
}

pub fn to_list_preserves_order_test() {
  zipper.from_list([1, 2, 3])
  |> result_unwrap()
  |> zipper.down()
  |> zipper.to_list()
  |> should.equal([1, 2, 3])
}

pub fn replace_changes_only_the_focus_test() {
  zipper.from_list([1, 2, 3])
  |> result_unwrap()
  |> zipper.down()
  |> zipper.replace(20)
  |> zipper.to_list()
  |> should.equal([1, 20, 3])
}

fn result_unwrap(result: Result(a, Nil)) -> a {
  case result {
    Ok(value) -> value
    Error(_) -> panic as "expected Ok"
  }
}
