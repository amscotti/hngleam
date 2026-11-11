//// Pure URL builders for the two APIs the application talks to.

import gleam/int
import gleam/uri
import hngleam/domain/feed.{type Feed}
import hngleam/domain/item_id.{type ItemId}
import hngleam/domain/query.{type SearchQuery}

/// The Firebase Hacker News API.
pub const api_base: String = "https://hacker-news.firebaseio.com/v0"

/// The Algolia Hacker News Search API.
pub const search_base: String = "https://hn.algolia.com/api/v1/search"

/// The URL that lists a feed's story identifiers.
pub fn feed_url(feed: Feed) -> String {
  api_base <> "/" <> feed.endpoint(feed) <> ".json"
}

/// The URL of a single item.
pub fn item_url(id: ItemId) -> String {
  api_base <> "/item/" <> item_id.to_string(id) <> ".json"
}

/// The URL of a single item, from a raw integer identifier.
pub fn item_url_int(id: Int) -> String {
  api_base <> "/item/" <> int.to_string(id) <> ".json"
}

/// The URL of a search for stories matching the query.
pub fn search_url(query: SearchQuery) -> String {
  search_base
  <> "?query="
  <> uri.percent_encode(query.to_string(query))
  <> "&tags=story"
}
