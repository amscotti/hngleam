//// The five Hacker News feeds the application can browse.

import gleam/int
import gleam/list
import gleam/string

/// One of the five Hacker News story feeds.
pub type Feed {
  Top
  New
  Best
  Ask
  Show
}

/// Every feed, in tab order.
pub fn all() -> List(Feed) {
  [Top, New, Best, Ask, Show]
}

/// The feed after this one, wrapping around at the end. Used by Tab.
pub fn next(feed: Feed) -> Feed {
  case feed {
    Top -> New
    New -> Best
    Best -> Ask
    Ask -> Show
    Show -> Top
  }
}

/// The feed on a numbered tab, `1` to `5`.
pub fn from_digit(digit: String) -> Result(Feed, Nil) {
  case digit {
    "1" -> Ok(Top)
    "2" -> Ok(New)
    "3" -> Ok(Best)
    "4" -> Ok(Ask)
    "5" -> Ok(Show)
    _ -> Error(Nil)
  }
}

/// The human readable name of the feed.
pub fn label(feed: Feed) -> String {
  case feed {
    Top -> "Top"
    New -> "New"
    Best -> "Best"
    Ask -> "Ask HN"
    Show -> "Show HN"
  }
}

/// The number shown in front of the feed name in the tab row.
pub fn index(feed: Feed) -> Int {
  case feed {
    Top -> 1
    New -> 2
    Best -> 3
    Ask -> 4
    Show -> 5
  }
}

/// The feed tab as it appears in the tab row, e.g. `1:Top`.
pub fn tab_label(feed: Feed) -> String {
  int.to_string(index(feed)) <> ":" <> label(feed)
}

/// The Firebase API endpoint that lists this feed's story identifiers.
pub fn endpoint(feed: Feed) -> String {
  case feed {
    Top -> "topstories"
    New -> "newstories"
    Best -> "beststories"
    Ask -> "askstories"
    Show -> "showstories"
  }
}

/// Every tab label, in tab order.
pub fn tab_labels() -> List(String) {
  all() |> list.map(tab_label)
}

/// The width of the widest tab label, so the tab row never jitters.
pub fn tab_width() -> Int {
  tab_labels()
  |> list.map(string.length)
  |> list.fold(0, int.max)
}
