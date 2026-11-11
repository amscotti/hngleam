//// A search query that is known to be non-empty once trimmed.

import gleam/string

pub opaque type SearchQuery {
  SearchQuery(String)
}

/// Build a search query from raw user input. Whitespace-only input is
/// rejected, and surrounding whitespace is removed.
pub fn parse(raw: String) -> Result(SearchQuery, Nil) {
  let trimmed = string.trim(raw)
  case trimmed {
    "" -> Error(Nil)
    _ -> Ok(SearchQuery(trimmed))
  }
}

/// The query text.
pub fn to_string(query: SearchQuery) -> String {
  let SearchQuery(value) = query
  value
}
