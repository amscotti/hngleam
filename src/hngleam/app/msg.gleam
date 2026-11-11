//// Messages the application reacts to: key presses, results of work that ran
//// in another process, and ticks.

import gleam/option.{type Option}
import gleam/time/timestamp.{type Timestamp}
import hngleam/app/error.{type AppError}
import hngleam/app/model.{type Generation}
import hngleam/domain/comment.{type Comment}
import hngleam/domain/feed.{type Feed}
import hngleam/domain/item_id.{type ItemId}
import hngleam/domain/story.{type Story, type StoryBatch}
import hngleam/domain/terminal_size.{type TerminalSize}

/// A command the user asked for, independent of which key produced it.
pub type Action {
  Next
  Previous
  NextFeed
  SelectFeed(Feed)
  OpenStory
  OpenDetail
  OpenComment
  Back
  Reload
  StartSearch
  CancelSearch
  SubmitSearch
  Typed(String)
  Erase
  CursorLeft
  CursorRight
  CursorHome
  CursorEnd
  DeleteForward
  Quit
}

/// Everything the update function understands.
pub type Msg {
  /// A key press that the keymap translated into an action.
  Pressed(action: Action)
  /// A feed's stories arrived (or failed to).
  StoriesLoaded(
    feed: Feed,
    generation: Generation,
    result: Result(StoryBatch, AppError),
  )
  /// A story's comment tree arrived (or failed to).
  CommentsLoaded(
    story: ItemId,
    generation: Generation,
    result: Result(#(List(Comment), Int), AppError),
  )
  /// Search results arrived (or failed to).
  SearchLoaded(generation: Generation, result: Result(List(Story), AppError))
  /// The periodic tick that refreshes the clock and the terminal size.
  Ticked(size: Option(TerminalSize), now: Timestamp)
  /// The browser was asked to open a URL.
  BrowserResult(result: Result(Nil, AppError))
  /// Nothing to do; used by commands that exit the application.
  NoOp
}
