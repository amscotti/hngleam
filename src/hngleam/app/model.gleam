//// The application state.
////
//// Illegal states are not representable: a story that is being read is carried
//// by the `Reading` screen, search only exists as `Searching(Search)`, a
//// comment selection is always a non-empty zipper, and every in-flight
//// request is tagged with the generation it belongs to.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import hngleam/app/error.{type AppError}
import hngleam/domain/comment.{type Comment}
import hngleam/domain/feed.{type Feed}
import hngleam/domain/listing.{type Listing, Empty, NonEmpty}
import hngleam/domain/query.{type SearchQuery}
import hngleam/domain/story.{type Story}
import hngleam/domain/terminal_size.{type TerminalSize}
import hngleam/domain/zipper.{type Zipper}

/// A token identifying one request. Results carrying a stale generation are
/// ignored, so an old feed can never overwrite a newer one.
pub opaque type Generation {
  Generation(Int)
}

/// The first generation of a session.
pub fn first_generation() -> Generation {
  Generation(1)
}

/// The generation after this one.
pub fn next_generation(generation: Generation) -> Generation {
  let Generation(value) = generation
  Generation(value + 1)
}

/// The number behind a generation, for tests and debugging.
pub fn generation_value(generation: Generation) -> Int {
  let Generation(value) = generation
  value
}

/// True when two generations identify the same request.
pub fn same_generation(a: Generation, b: Generation) -> Bool {
  generation_value(a) == generation_value(b)
}

/// The state of data that has to be fetched.
pub type Remote(a) {
  NotAsked
  Loading(Generation)
  Loaded(a)
  Failed(AppError)
}

/// Where the detail screen goes back to. A search is carried here so that
/// leaving a story returns to the same results.
pub type ReturnTo {
  BackToFeed
  BackToSearch(Search)
}

/// The state of a search.
pub type SearchOutcome {
  SearchInFlight(query: SearchQuery, generation: Generation)
  SearchFound(query: SearchQuery, stories: Listing(Story))
  SearchFailed(query: SearchQuery, error: AppError)
}

/// The search screen is either capturing a query or showing a result.
/// `cursor` is a grapheme index into `draft`.
pub type Search {
  Editing(draft: String, cursor: Int, previous: Option(SearchOutcome))
  Showing(outcome: SearchOutcome)
}

/// A level of the comment tree that has been left behind, with the selection
/// it had, so that going back returns to the same comment.
pub type Crumb {
  Crumb(level: Zipper(Comment), parent: Comment)
}

/// The comment tree being browsed: the current level plus the trail of levels
/// above it.
pub type CommentNav {
  CommentNav(current: Zipper(Comment), trail: List(Crumb))
}

/// A loaded comment tree: either a story with no comments at all, or a
/// navigation state, which can only exist when there is at least one comment.
pub type CommentTree {
  NoComments
  Comments(CommentNav)
}

/// The screen the user is looking at.
pub type Screen {
  Browsing
  Reading(story: Story, return_to: ReturnTo, comments: Remote(CommentTree))
  Searching(Search)
}

/// Everything the UI needs to draw a frame.
pub type Model {
  Model(
    feed: Feed,
    stories: Remote(Listing(Story)),
    screen: Screen,
    generation: Generation,
    size: TerminalSize,
    now: Timestamp,
    notice: Option(String),
  )
}

/// How deep into a comment thread the current level is.
pub fn comment_depth(nav: CommentNav) -> Int {
  list.length(nav.trail) + 1
}

/// The comment currently selected, if any.
pub fn selected_comment(nav: CommentNav) -> Comment {
  nav.current |> zipper.current()
}

/// Build a navigation state from a non-empty comment listing.
pub fn comment_nav_from(listing: Listing(Comment)) -> CommentTree {
  case listing {
    Empty -> NoComments
    NonEmpty(zipper) -> Comments(CommentNav(current: zipper, trail: []))
  }
}

/// The parent comment shown in the context header, when nested.
pub fn parent_comment(nav: CommentNav) -> Option(Comment) {
  case nav.trail {
    [] -> None
    [crumb, ..] -> Some(crumb.parent)
  }
}

/// Start editing a search, remembering any result that was already showing.
pub fn begin_search(previous: Option(SearchOutcome)) -> Search {
  case previous {
    Some(SearchFound(query:, ..)) -> {
      let draft = query.to_string(query)
      Editing(draft:, cursor: string.length(draft), previous:)
    }
    _ -> Editing(draft: "", cursor: 0, previous:)
  }
}
