//// Decoding Algolia's Hacker News Search API into domain values.

import gleam/dynamic/decode.{type DecodeError, DecodeError}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import hngleam/decode/hn
import hngleam/domain/item_id
import hngleam/domain/story.{type Story, Story}
import hngleam/text/html

/// One search hit, as Algolia describes it.
pub type RawHit {
  RawHit(
    object_id: String,
    title: Option(String),
    url: Option(String),
    author: Option(String),
    points: Option(Int),
    created_at: Int,
    num_comments: Option(Int),
  )
}

/// Decode a search response into stories, dropping hits that are not stories
/// (polls, comments) or that have no title.
pub fn decode_search(body: String) -> Result(List(Story), List(DecodeError)) {
  case decode_json(body, response_decoder()) {
    Ok(hits) -> Ok(list.filter_map(hits, to_story))
    Error(errors) -> Error(errors)
  }
}

/// Convert one hit into a story, if it is one.
pub fn to_story(hit: RawHit) -> Result(Story, Nil) {
  use id <- result.try(item_id.item_id_from_string(hit.object_id))
  use raw_title <- result.try(require_title(hit.title))
  let title = html.decode_entities(raw_title)
  case title == "" {
    True -> Error(Nil)
    False ->
      Ok(Story(
        id: id,
        title: title,
        url: clean(hit.url),
        author: clean(hit.author),
        score: option_unwrap(hit.points, 0) |> int.max(0),
        posted_at: hn.posted_at(hit.created_at),
        comment_count: option_unwrap(hit.num_comments, 0),
      ))
  }
}

fn response_decoder() -> decode.Decoder(List(RawHit)) {
  use hits <- decode.field("hits", decode.list(hit_decoder()))
  decode.success(hits)
}

fn hit_decoder() -> decode.Decoder(RawHit) {
  use object_id <- decode.field("objectID", decode.string)
  use title <- decode.optional_field(
    "title",
    None,
    decode.optional(decode.string),
  )
  use url <- decode.optional_field("url", None, decode.optional(decode.string))
  use author <- decode.optional_field(
    "author",
    None,
    decode.optional(decode.string),
  )
  use points <- decode.optional_field(
    "points",
    None,
    decode.optional(decode.int),
  )
  use created_at <- decode.optional_field(
    "created_at_i",
    0,
    decode.optional(decode.int)
      |> decode.map(fn(value) { option.unwrap(value, 0) }),
  )
  use num_comments <- decode.optional_field(
    "num_comments",
    None,
    decode.optional(decode.int),
  )
  decode.success(RawHit(
    object_id: object_id,
    title: title,
    url: url,
    author: author,
    points: points,
    created_at: created_at,
    num_comments: num_comments,
  ))
}

fn decode_json(
  body: String,
  using decoder: decode.Decoder(a),
) -> Result(a, List(DecodeError)) {
  case json.parse(from: body, using: decoder) {
    Ok(value) -> Ok(value)
    Error(json.UnableToDecode(errors)) -> Error(errors)
    Error(_) ->
      Error([
        DecodeError(expected: "JSON", found: "malformed document", path: []),
      ])
  }
}

fn require_title(title: Option(String)) -> Result(String, Nil) {
  case title {
    Some(value) if value != "" -> Ok(value)
    _ -> Error(Nil)
  }
}

fn clean(value: Option(String)) -> Option(String) {
  case value {
    Some(text) -> {
      let text = html.decode_entities(text)
      case text == "" {
        True -> None
        False -> Some(text)
      }
    }
    None -> None
  }
}

fn option_unwrap(value: Option(a), default: a) -> a {
  case value {
    Some(inner) -> inner
    None -> default
  }
}
