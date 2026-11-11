//// Manual smoke test against the live APIs. Not part of `gleam test`.
////
//// Run it with `gleam run -m dev/smoke` when you want to see how the real
//// client behaves, including timings.

import gleam/int
import gleam/io
import gleam/list
import gleam/time/duration
import gleam/time/timestamp
import hngleam/api/client
import hngleam/app/error
import hngleam/domain/feed

pub fn main() {
  let api = client.live()
  let start = timestamp.system_time()

  let stories = case api.fetch_stories(feed.Top) {
    Ok(batch) -> {
      io.println(
        "stories: "
        <> int.to_string(list.length(batch.stories))
        <> " failed: "
        <> int.to_string(batch.failed),
      )
      batch.stories
    }
    Error(problem) -> {
      io.println_error("stories failed: " <> error_text(problem))
      []
    }
  }

  let mid = timestamp.system_time()
  io.println(
    "fetch_stories took "
    <> int.to_string(duration.to_milliseconds(timestamp.difference(start, mid)))
    <> " ms",
  )

  case list.find(stories, fn(story) { story.comment_count > 200 }) {
    Error(_) -> io.println("no big threads to load")
    Ok(story) -> {
      io.println("comments for " <> story.title)
      let before = timestamp.system_time()
      case api.fetch_comments(story.id) {
        Ok(#(comments, failed)) ->
          io.println(
            "comments: "
            <> int.to_string(list.length(comments))
            <> " failed: "
            <> int.to_string(failed),
          )
        Error(problem) ->
          io.println_error("comments failed: " <> error_text(problem))
      }
      let after = timestamp.system_time()
      let millis = duration.to_milliseconds(timestamp.difference(before, after))
      io.println("fetch_comments took " <> int.to_string(millis) <> " ms")
    }
  }
}

fn error_text(problem: error.AppError) -> String {
  error.describe(problem)
}
