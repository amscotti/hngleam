//// Opaque identifiers for Hacker News items.
////
//// Hacker News item identifiers are positive integers. Both the Firebase API
//// and the Algolia search API expose them, the latter as a string, so all
//// conversion goes through this module and invalid identifiers cannot be
//// constructed anywhere else in the application.

import gleam/int
import gleam/string

pub opaque type ItemId {
  ItemId(Int)
}

/// Build an `ItemId` from an integer. Identifiers must be positive.
pub fn item_id(raw: Int) -> Result(ItemId, Nil) {
  case raw > 0 {
    True -> Ok(ItemId(raw))
    False -> Error(Nil)
  }
}

/// Build an `ItemId` from its textual form, as returned by Algolia's
/// `objectID` field.
pub fn item_id_from_string(raw: String) -> Result(ItemId, Nil) {
  case int.parse(string.trim(raw)) {
    Ok(value) -> item_id(value)
    Error(_) -> Error(Nil)
  }
}

/// The integer behind an identifier.
pub fn to_int(id: ItemId) -> Int {
  let ItemId(value) = id
  value
}

/// The identifier as a string, suitable for URLs.
pub fn to_string(id: ItemId) -> String {
  int.to_string(to_int(id))
}

/// The canonical Hacker News page for this item.
pub fn hn_url(id: ItemId) -> String {
  "https://news.ycombinator.com/item?id=" <> to_string(id)
}
