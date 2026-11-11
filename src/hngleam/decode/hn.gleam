//// Decoding the Firebase Hacker News API into domain values.
////
//// This is the only place where untyped JSON is understood. Everything that
//// leaves this module is a typed domain value, so no `Dynamic` reaches the
//// application or the UI.

import gleam/dynamic/decode.{type DecodeError, DecodeError}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/timestamp
import hngleam/domain/comment.{type Comment, Comment}
import hngleam/domain/item_id
import hngleam/domain/story.{type Story, Story}
import hngleam/text/html

/// A Hacker News item exactly as the API describes it, including the fields
/// that are only meaningful for some kinds of item.
pub type RawItem {
  RawItem(
    id: Int,
    kind: String,
    title: String,
    url: Option(String),
    author: Option(String),
    score: Int,
    time: Int,
    descendants: Option(Int),
    kids: List(Int),
    text: Option(String),
    deleted: Bool,
    dead: Bool,
  )
}

/// Decode a list of item identifiers, as returned by the feed endpoints.
pub fn decode_ids(body: String) -> Result(List(Int), List(DecodeError)) {
  decode_json(body, decode.list(decode.int))
}

/// Decode one item.
pub fn decode_item(body: String) -> Result(RawItem, List(DecodeError)) {
  decode_json(body, item_decoder())
}

/// Convert a raw item into a story, rejecting items that are not stories or
/// that have no title.
pub fn to_story(raw: RawItem) -> Result(Story, Nil) {
  use id <- result.try(item_id.item_id(raw.id))
  case is_gone(raw) || !is_story(raw) {
    True -> Error(Nil)
    False -> {
      let title = html.decode_entities(raw.title)
      case title {
        "" -> Error(Nil)
        title ->
          Ok(Story(
            id: id,
            title: title,
            url: clean(raw.url),
            author: clean(raw.author),
            score: int.max(raw.score, 0),
            posted_at: posted_at(raw.time),
            comment_count: option_unwrap(raw.descendants, 0),
          ))
      }
    }
  }
}

/// Convert a raw item into a comment. Deleted and dead comments, and comments
/// with no text, are dropped here so the rest of the application never has to
/// think about them.
pub fn to_comment(raw: RawItem) -> Result(Comment, Nil) {
  case raw.deleted || raw.dead {
    True -> Error(Nil)
    False ->
      case item_id.item_id(raw.id) {
        Error(_) -> Error(Nil)
        Ok(id) ->
          case clean(raw.text) {
            None -> Error(Nil)
            Some(body) ->
              Ok(
                Comment(
                  id: id,
                  author: clean(raw.author),
                  text: html.to_text(body),
                  posted_at: posted_at(raw.time),
                  replies: [],
                ),
              )
          }
      }
  }
}

/// A timestamp for an API value. Missing or negative times become the unix
/// epoch, which the layout renders as `-`.
pub fn posted_at(seconds: Int) -> timestamp.Timestamp {
  timestamp.from_unix_seconds(int.max(seconds, 0))
}

fn item_decoder() -> decode.Decoder(RawItem) {
  use id <- decode.field("id", decode.int)
  use kind <- decode.optional_field(
    "type",
    "story",
    or_default(decode.string, "story"),
  )
  use title <- decode.optional_field("title", "", or_default(decode.string, ""))
  use url <- decode.optional_field("url", None, decode.optional(decode.string))
  use author <- decode.optional_field(
    "by",
    None,
    decode.optional(decode.string),
  )
  use score <- decode.optional_field("score", 0, or_default(decode.int, 0))
  use time <- decode.optional_field("time", 0, or_default(decode.int, 0))
  use descendants <- decode.optional_field(
    "descendants",
    None,
    decode.optional(decode.int),
  )
  use kids <- decode.optional_field(
    "kids",
    None,
    decode.optional(decode.list(decode.int)),
  )
  use text <- decode.optional_field(
    "text",
    None,
    decode.optional(decode.string),
  )
  use deleted <- decode.optional_field(
    "deleted",
    False,
    or_default(decode.bool, False),
  )
  use dead <- decode.optional_field(
    "dead",
    False,
    or_default(decode.bool, False),
  )
  decode.success(RawItem(
    id: id,
    kind: kind,
    title: title,
    url: url,
    author: author,
    score: score,
    time: time,
    descendants: descendants,
    kids: option_unwrap(kids, []),
    text: text,
    deleted: deleted,
    dead: dead,
  ))
}

/// Decode a JSON document, normalising all parse failures into the same shape.
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

/// `optional_field` only substitutes the default when the key is absent.
/// A present `null` has to be decoded as an optional value and unwrapped.
fn or_default(decoder: decode.Decoder(a), default: a) -> decode.Decoder(a) {
  decode.optional(decoder)
  |> decode.map(fn(value) { option.unwrap(value, default) })
}

fn option_unwrap(value: Option(a), default: a) -> a {
  case value {
    Some(inner) -> inner
    None -> default
  }
}

/// The reply identifiers of an item, if it has any.
pub fn kids(raw: RawItem) -> List(Int) {
  raw.kids
}

/// The first `count` identifiers, in order.
pub fn take_ids(ids: List(Int), count: Int) -> List(Int) {
  list.take(ids, count)
}

/// True when the item is a story, job, poll, or poll option.
pub fn is_story(raw: RawItem) -> Bool {
  case raw.kind {
    "story" | "job" | "poll" | "pollopt" -> True
    _ -> False
  }
}

/// True when the raw item has been removed from Hacker News.
pub fn is_gone(raw: RawItem) -> Bool {
  raw.deleted || raw.dead
}

/// A short description of a raw item's kind, used in error messages.
pub fn kind(raw: RawItem) -> String {
  raw.kind
}
