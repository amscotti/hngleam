//// Stories as the application understands them.

import gleam/option.{type Option, None, Some}
import gleam/time/timestamp.{type Timestamp}
import hngleam/domain/item_id.{type ItemId}

/// A story as shown in a feed or in search results.
pub type Story {
  Story(
    id: ItemId,
    title: String,
    url: Option(String),
    author: Option(String),
    score: Int,
    posted_at: Timestamp,
    comment_count: Int,
  )
}

/// The outcome of loading a feed: the stories that arrived, plus a count of
/// the ones that failed. Individual failures never fail the whole feed.
pub type StoryBatch {
  StoryBatch(stories: List(Story), failed: Int)
}

/// The URL to open for a story: the story's own link, or its Hacker News page
/// when it has none (Ask HN, text posts).
pub fn link(story: Story) -> String {
  case story.url {
    Some(url) if url != "" -> url
    _ -> item_id.hn_url(story.id)
  }
}

/// The link shown under the title, when the story has one.
pub fn shown_url(story: Story) -> Option(String) {
  case story.url {
    Some(url) if url != "" -> Some(url)
    _ -> None
  }
}
