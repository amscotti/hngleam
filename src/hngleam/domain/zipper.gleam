//// A non-empty selection: a focus with the elements before and after it.
////
//// A `Zipper` always contains at least one element and its focus is always a
//// real value, so "selected index out of range" cannot be represented. The
//// `before` list is stored nearest-first.

import gleam/list

pub opaque type Zipper(a) {
  Zipper(before: List(a), focus: a, after: List(a))
}

/// Build a zipper positioned on the first element. An empty list has no valid
/// selection, so it is rejected.
pub fn from_list(items: List(a)) -> Result(Zipper(a), Nil) {
  case items {
    [] -> Error(Nil)
    [first, ..rest] -> Ok(Zipper(before: [], focus: first, after: rest))
  }
}

/// The focused element.
pub fn current(zipper: Zipper(a)) -> a {
  let Zipper(focus:, ..) = zipper
  focus
}

/// The position of the focus, counting from zero.
pub fn index(zipper: Zipper(a)) -> Int {
  let Zipper(before:, ..) = zipper
  list.length(before)
}

/// How many elements the zipper holds.
pub fn length(zipper: Zipper(a)) -> Int {
  let Zipper(before:, after:, ..) = zipper
  list.length(before) + 1 + list.length(after)
}

/// Every element, in order.
pub fn to_list(zipper: Zipper(a)) -> List(a) {
  let Zipper(before:, focus:, after:) = zipper
  list.append(list.reverse(before), [focus, ..after])
}

/// Move the focus one element forward, stopping at the last element.
pub fn down(zipper: Zipper(a)) -> Zipper(a) {
  case zipper {
    Zipper(before:, focus:, after: []) -> Zipper(before:, focus:, after: [])
    Zipper(before:, focus:, after: [next, ..rest]) ->
      Zipper(before: [focus, ..before], focus: next, after: rest)
  }
}

/// Move the focus one element backward, stopping at the first element.
pub fn up(zipper: Zipper(a)) -> Zipper(a) {
  case zipper {
    Zipper(before: [], focus:, after:) -> Zipper(before: [], focus:, after:)
    Zipper(before: [previous, ..rest], focus:, after:) ->
      Zipper(before: rest, focus: previous, after: [focus, ..after])
  }
}

/// Replace the focused element.
pub fn replace(zipper: Zipper(a), value: a) -> Zipper(a) {
  let Zipper(before:, after:, ..) = zipper
  Zipper(before:, focus: value, after:)
}

/// Apply a function to every element, keeping the focus position.
pub fn map(zipper: Zipper(a), with: fn(a) -> b) -> Zipper(b) {
  let Zipper(before:, focus:, after:) = zipper
  Zipper(
    before: list.map(before, with),
    focus: with(focus),
    after: list.map(after, with),
  )
}
