import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/time/timestamp
import gleeunit/should
import hngleam/api/comments
import hngleam/app/error.{type AppError, Network}
import hngleam/domain/comment.{type Comment, Comment}
import hngleam/domain/item_id

pub fn top_level_comments_are_capped_test() {
  let kids = numbers(1, 60)
  let fetcher = fetcher_for(kids)
  let #(loaded, _failures) = build(kids, fetcher)
  loaded |> list.length() |> should.equal(comments.max_top_level)
}

pub fn replies_are_capped_per_comment_test() {
  // Comment 1 has fifteen children; only ten are fetched.
  let children = numbers(100, 114)
  let fetcher = fn(id: Int) {
    case id {
      1 -> Ok(Some(comment_at(1, children)))
      _ -> Ok(Some(comment_at(id, [])))
    }
  }
  let #(loaded, _failures) = build([1], fetcher)
  let root = loaded |> first_comment()
  root.replies |> list.length() |> should.equal(comments.max_replies)
}

pub fn nesting_stops_at_four_levels_test() {
  // A chain: 1 -> 2 -> 3 -> 4 -> 5 -> 6
  let fetcher = fetcher_for_chain(6)
  let #(loaded, _failures) = build([1], fetcher)
  depth_of(loaded) |> should.equal(comments.max_depth)
}

pub fn deleted_comments_are_dropped_test() {
  let fetcher = fn(id: Int) { deleted(id) }
  let #(loaded, failures) = build([1, 2, 3], fetcher)
  loaded |> list.length() |> should.equal(0)
  failures |> should.equal(0)
}

pub fn failures_are_counted_and_reported_when_nothing_loads_test() {
  let fetcher = fn(_id: Int) { Error(Network(reason: "offline")) }
  case comments.build([1, 2], fetcher) {
    Ok(_) -> panic as "expected an error"
    Error(Network(reason:)) -> reason |> should.equal("offline")
    Error(_) -> panic as "unexpected error"
  }
}

pub fn one_failure_does_not_lose_the_others_test() {
  let fetcher = fn(id: Int) {
    case id {
      1 -> Ok(Some(comment_at(id, [])))
      _ -> Error(Network(reason: "offline"))
    }
  }
  let #(loaded, failures) = build([1, 2], fetcher)
  loaded |> list.length() |> should.equal(1)
  failures |> should.equal(1)
}

// Fixtures

fn comment_at(id: Int, kids: List(Int)) -> comments.Fetched {
  comments.Fetched(
    comment: Comment(
      id: item_id_at(id),
      author: Some("someone"),
      text: "a comment",
      posted_at: timestamp.from_unix_seconds(0),
      replies: [],
    ),
    kids: kids,
  )
}

fn deleted(_id: Int) -> Result(Option(comments.Fetched), AppError) {
  Ok(None)
}

fn fetcher_for(
  ids: List(Int),
) -> fn(Int) -> Result(Option(comments.Fetched), AppError) {
  fn(id: Int) {
    case list.contains(ids, id) {
      True -> Ok(Some(comment_at(id, [])))
      False -> Ok(None)
    }
  }
}

/// 1 -> 2 -> 3 -> ... each comment has exactly one child.
fn fetcher_for_chain(
  length: Int,
) -> fn(Int) -> Result(Option(comments.Fetched), AppError) {
  fn(id: Int) {
    case id < length {
      True -> Ok(Some(comment_at(id, [id + 1])))
      False -> Ok(Some(comment_at(id, [])))
    }
  }
}

fn build(
  kids: List(Int),
  fetcher: fn(Int) -> Result(Option(comments.Fetched), AppError),
) -> #(List(Comment), Int) {
  case comments.build(kids, fetcher) {
    Ok(result) -> result
    Error(_) -> #([], 0)
  }
}

fn depth_of(comments: List(Comment)) -> Int {
  case comments {
    [] -> 0
    [comment, ..] -> 1 + depth_of(comment.replies)
  }
}

fn first_comment(comments: List(Comment)) -> Comment {
  case comments {
    [comment, ..] -> comment
    [] -> panic as "expected a comment"
  }
}

fn item_id_at(value: Int) -> item_id.ItemId {
  case item_id.item_id(value) {
    Ok(id) -> id
    Error(_) -> panic as "invalid id"
  }
}

fn numbers(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..numbers(from + 1, to)]
  }
}
