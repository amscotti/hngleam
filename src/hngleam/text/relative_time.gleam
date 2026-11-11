//// Compact relative timestamps, in the style of Hacker News itself.

import gleam/float
import gleam/int
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}

/// Render the distance between `then` and `now` as `now`, `5m`, `3h` or `2d`.
/// A missing timestamp is stored as the unix epoch and rendered as `-`.
pub fn relative(now now: Timestamp, then then: Timestamp) -> String {
  case timestamp.to_unix_seconds(then) <=. 0.0 {
    True -> "-"
    False -> relative_seconds(now, then)
  }
}

fn relative_seconds(now: Timestamp, then: Timestamp) -> String {
  let seconds =
    timestamp.difference(then, now)
    |> duration.to_seconds()
    |> float.truncate

  case seconds {
    seconds if seconds < 45 -> "now"
    seconds if seconds < 3600 -> int.to_string(seconds / 60) <> "m"
    seconds if seconds < 86_400 -> int.to_string(seconds / 3600) <> "h"
    seconds -> {
      let days = seconds / 86_400
      case days >= 365 {
        True -> int.to_string(days / 365) <> "y"
        False -> int.to_string(days) <> "d"
      }
    }
  }
}
