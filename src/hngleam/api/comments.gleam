//// Turning a story's flat list of child identifiers into a comment tree.
////
//// The Hacker News API only gives identifiers, so the tree is built a level at
//// a time: every comment at a depth is fetched in one parallel batch, then the
//// next depth is fetched for all of them at once. Fetching replies per parent
//// instead would serialise the whole load behind fifty round trips.
////
//// A thread is capped at 50 top-level comments, four levels of replies, and 10
//// replies per comment. A global budget stops one story from generating
//// thousands of requests; anything beyond it is left for the key that opens
//// the thread on Hacker News.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import hngleam/api/parallel
import hngleam/app/error.{type AppError, Timeout}
import hngleam/domain/comment.{type Comment, Comment}
import hngleam/domain/item_id

/// A comment plus the identifiers of its replies, before the tree is built.
pub type Fetched {
  Fetched(comment: Comment, kids: List(Int))
}

/// The maximum number of top-level comments fetched for a story.
pub const max_top_level: Int = 50

/// How deep replies are followed.
pub const max_depth: Int = 4

/// The maximum number of replies fetched per comment.
pub const max_replies: Int = 10

/// A hard ceiling on the total number of comments fetched for one story.
pub const max_comments: Int = 400

const concurrency: Int = 16

const timeout_ms: Int = 10_000

/// Build the comment tree for a story's `kids`, fetching comments with the
/// supplied function. Returns the top-level comments and the number that could
/// not be loaded.
pub fn build(
  kids: List(Int),
  with fetch: fn(Int) -> Result(Option(Fetched), AppError),
) -> Result(#(List(Comment), Int), AppError) {
  let top_ids = list.take(kids, max_top_level)
  case top_ids {
    [] -> Ok(#([], 0))
    _ -> {
      let #(level, failures, first_error) = fetch_level(top_ids, fetch)
      let #(comments, inner_failures, inner_error, _budget) =
        deepen(level, 2, max_comments - list.length(top_ids), fetch)
      let failures = failures + inner_failures
      let first_error = case first_error {
        Some(error) -> Some(error)
        None -> inner_error
      }
      case comments, first_error {
        [], Some(error) if failures > 0 -> Error(error)
        _, _ -> Ok(#(comments, failures))
      }
    }
  }
}

/// Fetch one depth: all of these identifiers in a single parallel batch.
fn fetch_level(
  ids: List(Int),
  fetch: fn(Int) -> Result(Option(Fetched), AppError),
) -> #(List(Fetched), Int, Option(AppError)) {
  ids
  |> parallel.map(concurrency, timeout_ms, fetch)
  |> classify()
}

fn classify(
  results: List(Option(Result(Option(Fetched), AppError))),
) -> #(List(Fetched), Int, Option(AppError)) {
  let #(loaded, failures, first_error) =
    list.fold(results, #([], 0, None), fn(acc, result) {
      let #(loaded, failures, first_error) = acc
      case result {
        Some(Ok(Some(fetched))) -> #([fetched, ..loaded], failures, first_error)
        // A deleted or dead comment is not a failure.
        Some(Ok(None)) -> acc
        Some(Error(error)) -> #(
          loaded,
          failures + 1,
          remember(first_error, error),
        )
        None -> #(loaded, failures + 1, remember(first_error, Timeout))
      }
    })
  #(list.reverse(loaded), failures, first_error)
}

/// Fetch every level below `parents`, then hang the replies off their parents.
fn deepen(
  parents: List(Fetched),
  depth: Int,
  budget: Int,
  fetch: fn(Int) -> Result(Option(Fetched), AppError),
) -> #(List(Comment), Int, Option(AppError), Int) {
  let ids =
    parents
    |> list.flat_map(fn(parent) { list.take(parent.kids, max_replies) })
    |> list.take(int.max(budget, 0))

  case depth > max_depth || ids == [] {
    True -> #(list.map(parents, fn(parent) { parent.comment }), 0, None, budget)
    False -> {
      let #(fetched, failures, first_error) = fetch_level(ids, fetch)
      let #(descendants, inner_failures, inner_error, remaining) =
        deepen(fetched, depth + 1, budget - list.length(ids), fetch)
      let by_id =
        dict.from_list(
          list.map(descendants, fn(comment) {
            #(item_id.to_int(comment.id), comment)
          }),
        )

      let comments =
        list.map(parents, fn(parent) {
          let replies =
            parent.kids
            |> list.take(max_replies)
            |> list.filter_map(fn(kid) { dict.get(by_id, kid) })
          Comment(..parent.comment, replies: replies)
        })

      let first_error = case first_error {
        Some(error) -> Some(error)
        None -> inner_error
      }
      #(comments, failures + inner_failures, first_error, remaining)
    }
  }
}

/// The first error seen, so the user is told about the real cause rather than
/// a generic message.
fn remember(current: Option(AppError), error: AppError) -> Option(AppError) {
  case current {
    Some(_) -> current
    None -> Some(error)
  }
}
