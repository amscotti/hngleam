import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import hngleam/decode/hn
import hngleam/domain/comment.{type Comment}
import hngleam/domain/item_id
import hngleam/domain/story
import simplifile

pub fn feed_ids_decode_test() {
  let ids = decode_ids("topstories.json")
  ids |> list.length() |> should.equal(30)
  ids |> list.all(fn(id) { id > 0 }) |> should.be_true()
}

pub fn story_with_url_decodes_test() {
  let decoded = story_of("story.json")
  decoded.title |> should.not_equal("")
  decoded.url |> should.be_some()
  { decoded.score > 0 } |> should.be_true()
  { decoded.comment_count > 0 } |> should.be_true()
  decoded.author |> should.be_some()
}

pub fn ask_hn_story_has_no_url_and_falls_back_to_hn_test() {
  let decoded = story_of("ask_story.json")
  decoded.url |> should.equal(None)
  story.link(decoded)
  |> should.equal(
    "https://news.ycombinator.com/item?id=" <> item_id.to_string(decoded.id),
  )
}

pub fn story_without_a_comment_count_test() {
  story_of("story_no_comments.json").comment_count |> should.equal(0)
}

pub fn comment_decodes_to_plain_text_test() {
  let decoded = comment_of("comment.json")
  decoded.text |> should.not_equal("")
  decoded.text |> string.contains("<") |> should.be_false()
  decoded.text |> string.contains("&#x27;") |> should.be_false()
}

pub fn deleted_comments_are_dropped_test() {
  let raw = item("deleted_comment.json")
  hn.to_comment(raw) |> should.be_error()
}

pub fn dead_comments_are_dropped_test() {
  let raw = item("dead_comment.json")
  hn.to_comment(raw) |> should.be_error()
}

pub fn null_fields_and_entities_decode_test() {
  let json =
    "{\"id\": 7, \"type\": null, \"title\": \"Hello &amp; Gleam\", \"by\": \"a&amp;b\", \"score\": null, \"time\": null, \"deleted\": null, \"dead\": null}"
  case hn.decode_item(json) {
    Error(_) -> panic as "expected the null fields to decode"
    Ok(raw) -> {
      raw.kind |> should.equal("story")
      raw.score |> should.equal(0)
      raw.time |> should.equal(0)
      case hn.to_story(raw) {
        Error(_) -> panic as "expected a story"
        Ok(decoded) -> {
          decoded.title |> should.equal("Hello & Gleam")
          decoded.author |> should.equal(Some("a&b"))
        }
      }
    }
  }
}

pub fn removed_and_non_story_items_are_dropped_test() {
  let gone =
    "{\"id\": 8, \"type\": \"story\", \"title\": \"gone\", \"dead\": true}"
  let comment =
    "{\"id\": 9, \"type\": \"comment\", \"title\": \"not a story\", \"text\": \"hi\"}"
  case hn.decode_item(gone) {
    Ok(raw) -> hn.to_story(raw) |> should.be_error()
    Error(_) -> panic as "expected the dead item to decode"
  }
  case hn.decode_item(comment) {
    Ok(raw) -> hn.to_story(raw) |> should.be_error()
    Error(_) -> panic as "expected the comment to decode"
  }
}

pub fn malformed_json_is_an_error_not_a_crash_test() {
  case hn.decode_item("{not json") {
    Ok(_) -> panic as "expected a decode error"
    Error(errors) -> { errors != [] } |> should.be_true()
  }
}

fn fixture(name: String) -> String {
  case simplifile.read("test/fixtures/" <> name) {
    Ok(contents) -> contents
    Error(_) -> panic as { "missing fixture " <> name }
  }
}

fn decode_ids(name: String) -> List(Int) {
  case hn.decode_ids(fixture(name)) {
    Ok(ids) -> ids
    Error(_) -> panic as "expected ids"
  }
}

fn item(name: String) -> hn.RawItem {
  case hn.decode_item(fixture(name)) {
    Ok(raw) -> raw
    Error(_) -> panic as "expected an item"
  }
}

fn story_of(name: String) -> story.Story {
  case hn.to_story(item(name)) {
    Ok(decoded) -> decoded
    Error(_) -> panic as "expected a story"
  }
}

fn comment_of(name: String) -> Comment {
  case hn.to_comment(item(name)) {
    Ok(decoded) -> decoded
    Error(_) -> panic as "expected a comment"
  }
}
