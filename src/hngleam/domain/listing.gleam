//// A list that is either empty or has a selection.

import gleam/list
import gleam/option.{type Option, None, Some}
import hngleam/domain/zipper.{type Zipper}

pub type Listing(a) {
  Empty
  NonEmpty(Zipper(a))
}

/// Build a listing from a plain list.
pub fn from_list(items: List(a)) -> Listing(a) {
  case zipper.from_list(items) {
    Ok(zipper) -> NonEmpty(zipper)
    Error(_) -> Empty
  }
}

/// The underlying elements in order.
pub fn to_list(listing: Listing(a)) -> List(a) {
  case listing {
    Empty -> []
    NonEmpty(zipper) -> zipper.to_list(zipper)
  }
}

/// How many elements the listing holds.
pub fn length(listing: Listing(a)) -> Int {
  case listing {
    Empty -> 0
    NonEmpty(zipper) -> zipper.length(zipper)
  }
}

/// The selected element, if there is one.
pub fn current(listing: Listing(a)) -> Option(a) {
  case listing {
    Empty -> None
    NonEmpty(zipper) -> Some(zipper.current(zipper))
  }
}

/// The selected index, if there is a selection.
pub fn index(listing: Listing(a)) -> Option(Int) {
  case listing {
    Empty -> None
    NonEmpty(zipper) -> Some(zipper.index(zipper))
  }
}

/// Move the selection forward, clamped at the last element.
pub fn next(listing: Listing(a)) -> Listing(a) {
  case listing {
    Empty -> Empty
    NonEmpty(zipper) -> NonEmpty(zipper.down(zipper))
  }
}

/// Move the selection backward, clamped at the first element.
pub fn previous(listing: Listing(a)) -> Listing(a) {
  case listing {
    Empty -> Empty
    NonEmpty(zipper) -> NonEmpty(zipper.up(zipper))
  }
}

/// Apply a function to every element, keeping the selection.
pub fn map(listing: Listing(a), with: fn(a) -> b) -> Listing(b) {
  case listing {
    Empty -> Empty
    NonEmpty(zipper) -> NonEmpty(zipper.map(zipper, with))
  }
}

/// True when there is nothing to show.
pub fn is_empty(listing: Listing(a)) -> Bool {
  case listing {
    Empty -> True
    NonEmpty(_) -> False
  }
}

/// The elements in order, paired with their index.
pub fn indexed(listing: Listing(a)) -> List(#(Int, a)) {
  list.index_map(to_list(listing), fn(item, index) { #(index, item) })
}
