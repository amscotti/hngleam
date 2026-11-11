import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import hngleam/api/client
import hngleam/app/error.{HttpStatus, Timeout}
import hngleam/decode/hn.{type RawItem, RawItem}
import hngleam/domain/item_id
import hngleam/domain/story.{StoryBatch}

pub fn stories_keep_feed_order_and_skip_non_stories_test() {
  let result =
    client.stories_from([
      Some(Ok(raw_story(1, "first"))),
      Some(Ok(raw_comment(2))),
      Some(Ok(RawItem(..raw_story(3, "untitled"), title: ""))),
      Some(Ok(RawItem(..raw_story(4, "gone"), dead: True))),
      Some(Ok(raw_story(5, "A &amp; B"))),
    ])

  case result {
    Ok(StoryBatch(stories:, failed:)) -> {
      failed |> should.equal(0)
      stories
      |> list.map(fn(story) { #(item_id.to_int(story.id), story.title) })
      |> should.equal([#(1, "first"), #(5, "A & B")])
    }
    Error(_) -> panic as "expected the stories to be kept"
  }
}

pub fn a_missing_item_counts_as_a_timeout_and_keeps_the_story_test() {
  let result =
    client.stories_from([
      Some(Ok(raw_story(1, "kept"))),
      None,
    ])

  case result {
    Ok(StoryBatch(stories:, failed:)) -> {
      failed |> should.equal(1)
      stories
      |> list.map(fn(story) { item_id.to_int(story.id) })
      |> should.equal([1])
    }
    Error(_) -> panic as "expected the story to be kept"
  }
}

pub fn every_item_failing_returns_the_first_error_test() {
  let first = HttpStatus(code: 503, endpoint: "a story")
  client.stories_from([
    Some(Error(first)),
    None,
    Some(Error(Timeout)),
  ])
  |> should.equal(Error(first))
}

pub fn a_feed_of_timeouts_returns_timeout_test() {
  client.stories_from([None, None]) |> should.equal(Error(Timeout))
}

pub fn a_lone_non_story_is_an_empty_feed_test() {
  client.stories_from([Some(Ok(raw_comment(2)))])
  |> should.equal(Ok(StoryBatch(stories: [], failed: 0)))
}

pub fn an_empty_id_list_is_an_empty_feed_test() {
  client.stories_from([])
  |> should.equal(Ok(StoryBatch(stories: [], failed: 0)))
}

fn raw_story(id: Int, title: String) -> RawItem {
  RawItem(
    id: id,
    kind: "story",
    title: title,
    url: Some("https://example.com/" <> int.to_string(id)),
    author: Some("alice"),
    score: 12,
    time: 1_700_000_000,
    descendants: Some(3),
    kids: [],
    text: None,
    deleted: False,
    dead: False,
  )
}

fn raw_comment(id: Int) -> RawItem {
  RawItem(..raw_story(id, ""), kind: "comment", text: Some("hello"))
}
