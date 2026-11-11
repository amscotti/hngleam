//// Effects the pure application logic can ask for, and the interpreter that
//// turns them into the thunks shore runs in separate processes.

import gleam/erlang/process
import gleam/float
import gleam/option
import gleam/time/timestamp
import hngleam/api/client.{type Client, Client}
import hngleam/app/model.{type Generation}
import hngleam/app/msg.{
  type Msg, BrowserResult, CommentsLoaded, NoOp, SearchLoaded, StoriesLoaded,
  Ticked,
}
import hngleam/domain/feed.{type Feed}
import hngleam/domain/item_id.{type ItemId}
import hngleam/domain/query.{type SearchQuery}
import hngleam/domain/terminal_size.{type TerminalSize}
import hngleam/platform/browser
import hngleam/platform/terminal

/// Something the application wants to happen in the outside world.
pub type Effect {
  FetchFeed(feed: Feed, generation: Generation)
  FetchComments(story: ItemId, generation: Generation)
  SearchStories(query: SearchQuery, generation: Generation)
  OpenUrl(url: String)
  ScheduleTick(after_ms: Int)
  ExitApp
}

/// Turn an effect into the `fn() -> Msg` closure shore will run, unlinked, in
/// its own process. No closure may fail: every failure becomes a message.
pub fn to_command(
  effect: Effect,
  client: Client,
  quit: process.Subject(Nil),
) -> fn() -> Msg {
  let Client(fetch_stories:, fetch_comments:, search:) = client

  case effect {
    FetchFeed(feed:, generation:) -> fn() {
      StoriesLoaded(feed:, generation:, result: fetch_stories(feed))
    }
    FetchComments(story:, generation:) -> fn() {
      CommentsLoaded(story:, generation:, result: fetch_comments(story))
    }
    SearchStories(query:, generation:) -> fn() {
      SearchLoaded(generation:, result: search(query))
    }
    OpenUrl(url:) -> fn() { BrowserResult(browser.open(url)) }
    ScheduleTick(after_ms:) -> fn() {
      let now = timestamp.system_time()
      wait_for_visible_change(after_ms, terminal.size(), minute_bucket(now))
    }
    ExitApp -> fn() {
      process.send(quit, Nil)
      NoOp
    }
  }
}

/// Sleep until the terminal size changes or the displayed minute rolls over.
/// An idle reader then does not rebuild the screen four times a second.
fn wait_for_visible_change(
  after_ms: Int,
  previous: Result(TerminalSize, Nil),
  previous_minute: Int,
) -> Msg {
  process.sleep(after_ms)
  let now = timestamp.system_time()
  let size = terminal.size()
  let minute = minute_bucket(now)
  case size != previous || minute != previous_minute {
    True -> Ticked(size: option.from_result(size), now:)
    False -> wait_for_visible_change(after_ms, previous, previous_minute)
  }
}

/// The minute shown in relative timestamps. The tick loop redraws when this
/// changes, rather than on every sleep.
pub fn minute_bucket(now: timestamp.Timestamp) -> Int {
  float.truncate(timestamp.to_unix_seconds(now)) / 60
}
