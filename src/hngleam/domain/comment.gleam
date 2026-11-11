//// Comments and their reply trees.

import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/time/timestamp.{type Timestamp}
import hngleam/domain/item_id.{type ItemId}

/// A comment as shown on the detail screen. Deleted and dead comments are
/// dropped at the API boundary, so they cannot appear here.
pub type Comment {
  Comment(
    id: ItemId,
    author: Option(String),
    text: String,
    posted_at: Timestamp,
    replies: List(Comment),
  )
}

/// The number of direct replies to a comment.
pub fn reply_count(comment: Comment) -> Int {
  list.length(comment.replies)
}

/// A reply count rendered for humans, e.g. `[3 replies]`.
pub fn reply_label(comment: Comment) -> String {
  let count = reply_count(comment)
  case count {
    0 -> ""
    1 -> "[1 reply]"
    _ -> "[" <> int.to_string(count) <> " replies]"
  }
}

/// The author, or `[deleted]` when the author is not available.
pub fn author_label(comment: Comment) -> String {
  case comment.author {
    Some(author) if author != "" -> author
    _ -> "[deleted]"
  }
}
