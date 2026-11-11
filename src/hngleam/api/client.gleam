//// The live API client: HTTP in, domain values out.
////
//// `Client` is a record of functions so that tests can substitute a fake and
//// so that the application never depends on HTTP directly.

import gleam/dynamic/decode.{type DecodeError}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import hngleam/api/comments
import hngleam/api/parallel
import hngleam/api/urls
import hngleam/app/error.{type AppError, Decode, HttpStatus, Timeout}
import hngleam/decode/algolia
import hngleam/decode/hn
import hngleam/domain/comment.{type Comment}
import hngleam/domain/feed.{type Feed}
import hngleam/domain/item_id.{type ItemId}
import hngleam/domain/query.{type SearchQuery}
import hngleam/domain/story.{type Story, type StoryBatch, StoryBatch}

/// How many stories are fetched for a feed.
pub const story_limit: Int = 75

/// The per-request timeout, in milliseconds.
pub const request_timeout_ms: Int = 10_000

/// How many requests are allowed to be in flight at once.
pub const concurrency: Int = 16

/// The functions the application needs from the outside world.
pub type Client {
  Client(
    fetch_stories: fn(Feed) -> Result(StoryBatch, AppError),
    fetch_comments: fn(ItemId) -> Result(#(List(Comment), Int), AppError),
    search: fn(SearchQuery) -> Result(List(Story), AppError),
  )
}

/// A client that talks to the real APIs.
pub fn live() -> Client {
  Client(
    fetch_stories: fetch_stories,
    fetch_comments: fetch_comments,
    search: search,
  )
}

/// Fetch a feed's stories, in feed order, tolerating individual failures.
pub fn fetch_stories(feed: Feed) -> Result(StoryBatch, AppError) {
  let endpoint = "the " <> feed.label(feed) <> " feed"
  use body <- result.try(get_json(urls.feed_url(feed), endpoint))
  use ids <- result.try(decoded(hn.decode_ids(body), endpoint))
  let ids = list.take(ids, story_limit)
  let results = parallel.map(ids, concurrency, request_timeout_ms, fetch_item)
  stories_from(results)
}

/// Turn per-item fetch results into a feed, in the order they were requested.
///
/// A story is kept. A comment, a removed item, or an item with no title is
/// skipped and is not a failure. A missing item counts as a timeout. When
/// every requested item failed, the first error is returned.
pub fn stories_from(
  results: List(Option(Result(hn.RawItem, AppError))),
) -> Result(StoryBatch, AppError) {
  let #(stories, failures, first_error) = classify_stories(results)

  case stories, first_error {
    [], Some(error) if failures > 0 -> Error(error)
    _, _ -> Ok(StoryBatch(stories: list.reverse(stories), failed: failures))
  }
}

/// Fetch a story's comment tree.
pub fn fetch_comments(id: ItemId) -> Result(#(List(Comment), Int), AppError) {
  use body <- result.try(get_json(urls.item_url(id), "the discussion"))
  use raw <- result.try(decoded(hn.decode_item(body), "the discussion"))
  comments.build(raw.kids, fetch_comment)
}

/// Search Hacker News through Algolia.
pub fn search(query: SearchQuery) -> Result(List(Story), AppError) {
  let endpoint = "search results"
  use body <- result.try(get_json(urls.search_url(query), endpoint))
  decoded(algolia.decode_search(body), endpoint)
}

fn fetch_item(raw_id: Int) -> Result(hn.RawItem, AppError) {
  use body <- result.try(get_json(urls.item_url_int(raw_id), "a story"))
  decoded(hn.decode_item(body), "a story")
}

fn fetch_comment(raw_id: Int) -> Result(Option(comments.Fetched), AppError) {
  case get_json(urls.item_url_int(raw_id), "a comment") {
    Error(error) -> Error(error)
    Ok(body) ->
      case hn.decode_item(body) {
        Error(errors) -> Error(Decode(endpoint: "a comment", errors: errors))
        Ok(raw) ->
          case hn.to_comment(raw) {
            // Deleted, dead and empty comments are simply not shown.
            Error(_) -> Ok(None)
            Ok(comment) ->
              Ok(Some(comments.Fetched(comment: comment, kids: raw.kids)))
          }
      }
  }
}

fn classify_stories(
  results: List(Option(Result(hn.RawItem, AppError))),
) -> #(List(Story), Int, Option(AppError)) {
  let #(stories, failures, first_error) =
    list.fold(results, #([], 0, None), fn(acc, result) {
      let #(stories, failures, first_error) = acc
      case result {
        Some(Ok(raw)) ->
          case hn.to_story(raw) {
            Ok(story) -> #([story, ..stories], failures, first_error)
            // A comment, poll part or untitled item is not a failure.
            Error(_) -> acc
          }
        Some(Error(error)) -> #(
          stories,
          failures + 1,
          remember(first_error, error),
        )
        None -> #(stories, failures + 1, remember(first_error, Timeout))
      }
    })
  #(stories, failures, first_error)
}

fn remember(current: Option(AppError), error: AppError) -> Option(AppError) {
  case current {
    Some(_) -> current
    None -> Some(error)
  }
}

fn decoded(
  result: Result(a, List(DecodeError)),
  endpoint: String,
) -> Result(a, AppError) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(Decode(endpoint: endpoint, errors: errors))
  }
}

fn get_json(url: String, endpoint: String) -> Result(String, AppError) {
  case http_get(url, request_timeout_ms) {
    #(200, body) -> Ok(body)
    #(0, reason) -> Error(error.from_transport(reason))
    #(code, _body) -> Error(HttpStatus(code: code, endpoint: endpoint))
  }
}

@external(erlang, "hngleam_http", "get")
fn http_get(url: String, timeout: Int) -> #(Int, String)
