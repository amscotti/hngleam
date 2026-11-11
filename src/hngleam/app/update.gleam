//// The pure state machine. `update` never touches the network, the terminal
//// or the clock: it takes a message and returns a new model plus a list of
//// effects for the shell to perform.

import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import hngleam/app/effect.{
  type Effect, ExitApp, FetchComments, FetchFeed, OpenUrl, ScheduleTick,
  SearchStories,
}
import hngleam/app/error
import hngleam/app/model as m
import hngleam/app/msg.{
  type Action, type Msg, Back, BrowserResult, CancelSearch, CommentsLoaded,
  CursorEnd, CursorHome, CursorLeft, CursorRight, DeleteForward, Erase, Next,
  NextFeed, NoOp, OpenComment, OpenDetail, OpenStory, Pressed, Previous, Quit,
  Reload, SearchLoaded, SelectFeed, StartSearch, StoriesLoaded, SubmitSearch,
  Ticked, Typed,
}
import hngleam/domain/comment
import hngleam/domain/feed
import hngleam/domain/item_id
import hngleam/domain/listing
import hngleam/domain/query
import hngleam/domain/story
import hngleam/domain/terminal_size
import hngleam/domain/zipper

/// How often the clock and terminal size are refreshed, in milliseconds.
pub const tick_ms: Int = 250

/// The longest search query that can be typed.
const max_query_length: Int = 120

/// Start browsing the top stories.
pub fn init(
  size: terminal_size.TerminalSize,
  now: Timestamp,
) -> #(m.Model, List(Effect)) {
  let generation = m.first_generation()
  #(
    m.Model(
      feed: feed.Top,
      stories: m.Loading(generation),
      screen: m.Browsing,
      generation: generation,
      size: size,
      now: now,
      notice: None,
    ),
    [
      FetchFeed(feed: feed.Top, generation: generation),
      ScheduleTick(after_ms: tick_ms),
    ],
  )
}

/// Apply a message.
pub fn update(model: m.Model, msg: Msg) -> #(m.Model, List(Effect)) {
  case msg {
    Pressed(action:) -> press(model, action)
    StoriesLoaded(feed:, generation:, result:) ->
      stories_loaded(model, feed, generation, result)
    CommentsLoaded(story:, generation:, result:) ->
      comments_loaded(model, story, generation, result)
    SearchLoaded(generation:, result:) ->
      search_loaded(model, generation, result)
    Ticked(size:, now:) -> {
      let model = m.Model(..model, now: now, size: option_or(size, model.size))
      #(model, [ScheduleTick(after_ms: tick_ms)])
    }
    BrowserResult(result:) -> browser_result(model, result)
    NoOp -> #(model, [])
  }
}

fn press(model: m.Model, action: Action) -> #(m.Model, List(Effect)) {
  case action {
    Next -> move(model, True)
    Previous -> move(model, False)
    NextFeed -> switch_feed(model, feed.next(model.feed))
    SelectFeed(target) ->
      case model.screen == m.Browsing && target == model.feed {
        True -> #(model, [])
        False -> switch_feed(model, target)
      }
    OpenDetail -> open_detail(model)
    OpenStory -> open_story(model)
    OpenComment -> open_comment(model)
    Back -> back(model)
    Reload -> reload(model)
    StartSearch -> start_search(model)
    CancelSearch -> cancel_search(model)
    SubmitSearch -> submit_search(model)
    Typed(character) -> type_character(model, character)
    Erase -> erase(model)
    CursorLeft -> move_cursor(model, -1)
    CursorRight -> move_cursor(model, 1)
    CursorHome -> move_cursor_to(model, 0)
    CursorEnd -> move_cursor_to_end(model)
    DeleteForward -> delete_forward(model)
    Quit -> #(model, [ExitApp])
  }
}

// Selection movement

fn move(model: m.Model, forward: Bool) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Browsing -> #(move_feed(model, forward), [])
    m.Reading(story:, return_to:, comments:) -> #(
      move_comments(model, story, return_to, comments, forward),
      [],
    )
    m.Searching(_) -> #(move_search(model, forward), [])
  }
}

fn move_feed(model: m.Model, forward: Bool) -> m.Model {
  case model.stories {
    m.Loaded(items) -> {
      let items = move_listing(items, forward)
      m.Model(..model, stories: m.Loaded(items), notice: None)
    }
    _ -> model
  }
}

fn move_comments(
  model: m.Model,
  story: story.Story,
  return_to: m.ReturnTo,
  comments: m.Remote(m.CommentTree),
  forward: Bool,
) -> m.Model {
  case comments {
    m.Loaded(m.Comments(nav)) -> {
      let current = case forward {
        True -> zipper.down(nav.current)
        False -> zipper.up(nav.current)
      }
      let nav = m.CommentNav(..nav, current:)
      m.Model(
        ..model,
        screen: m.Reading(
          story:,
          return_to:,
          comments: m.Loaded(m.Comments(nav)),
        ),
        notice: None,
      )
    }
    _ -> model
  }
}

fn move_search(model: m.Model, forward: Bool) -> m.Model {
  case model.screen {
    m.Searching(m.Showing(m.SearchFound(query:, stories:))) -> {
      let stories = move_listing(stories, forward)
      m.Model(
        ..model,
        screen: m.Searching(m.Showing(m.SearchFound(query:, stories:))),
        notice: None,
      )
    }
    _ -> model
  }
}

fn move_listing(
  items: listing.Listing(a),
  forward: Bool,
) -> listing.Listing(a) {
  case forward {
    True -> listing.next(items)
    False -> listing.previous(items)
  }
}

// Screens

fn open_detail(model: m.Model) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Browsing ->
      case model.stories {
        m.Loaded(items) ->
          case listing.current(items) {
            Some(found) -> enter_reading(model, found, m.BackToFeed)
            None -> #(model, [])
          }
        _ -> #(model, [])
      }
    m.Searching(m.Showing(m.SearchFound(_, items)) as search) ->
      case listing.current(items) {
        Some(found) -> enter_reading(model, found, m.BackToSearch(search))
        None -> #(model, [])
      }
    m.Searching(_) -> #(model, [])
    m.Reading(story:, return_to:, comments:) ->
      drill_into_comment(model, story, return_to, comments)
  }
}

fn enter_reading(
  model: m.Model,
  story: story.Story,
  return_to: m.ReturnTo,
) -> #(m.Model, List(Effect)) {
  let generation = m.next_generation(model.generation)
  let model =
    m.Model(
      ..model,
      generation:,
      screen: m.Reading(story:, return_to:, comments: m.Loading(generation)),
      notice: None,
    )
  #(model, [FetchComments(story: story.id, generation:)])
}

fn drill_into_comment(
  model: m.Model,
  story: story.Story,
  return_to: m.ReturnTo,
  comments: m.Remote(m.CommentTree),
) -> #(m.Model, List(Effect)) {
  case comments {
    m.Loaded(m.Comments(nav)) -> {
      let selected = zipper.current(nav.current)
      case zipper.from_list(selected.replies) {
        Error(_) -> #(model, [])
        Ok(next_level) -> {
          let crumb = m.Crumb(level: nav.current, parent: selected)
          let nav =
            m.CommentNav(current: next_level, trail: [crumb, ..nav.trail])
          let model =
            m.Model(
              ..model,
              screen: m.Reading(
                story:,
                return_to:,
                comments: m.Loaded(m.Comments(nav)),
              ),
              notice: None,
            )
          #(model, [])
        }
      }
    }
    _ -> #(model, [])
  }
}

fn back(model: m.Model) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Reading(story:, return_to:, comments:) ->
      case comments {
        m.Loaded(m.Comments(nav)) ->
          case nav.trail {
            [crumb, ..rest] -> {
              let nav = m.CommentNav(current: crumb.level, trail: rest)
              let model =
                m.Model(
                  ..model,
                  screen: m.Reading(
                    story:,
                    return_to:,
                    comments: m.Loaded(m.Comments(nav)),
                  ),
                  notice: None,
                )
              #(model, [])
            }
            [] -> #(leave_reading(model, return_to), [])
          }
        _ -> #(leave_reading(model, return_to), [])
      }
    m.Searching(_) -> cancel_search(model)
    m.Browsing -> #(model, [])
  }
}

fn leave_reading(model: m.Model, return_to: m.ReturnTo) -> m.Model {
  case return_to {
    m.BackToFeed -> m.Model(..model, screen: m.Browsing)
    m.BackToSearch(search) -> m.Model(..model, screen: m.Searching(search))
  }
}

fn switch_feed(model: m.Model, target: feed.Feed) -> #(m.Model, List(Effect)) {
  let generation = m.next_generation(model.generation)
  let model =
    m.Model(
      ..model,
      feed: target,
      generation:,
      stories: m.Loading(generation),
      screen: m.Browsing,
      notice: None,
    )
  #(model, [FetchFeed(feed: target, generation:)])
}

fn reload(model: m.Model) -> #(m.Model, List(Effect)) {
  let generation = m.next_generation(model.generation)
  case model.screen {
    m.Browsing -> {
      let model =
        m.Model(
          ..model,
          generation:,
          stories: m.Loading(generation),
          notice: None,
        )
      #(model, [FetchFeed(feed: model.feed, generation:)])
    }
    m.Reading(story:, return_to:, comments: _) -> {
      let model =
        m.Model(
          ..model,
          generation:,
          screen: m.Reading(story:, return_to:, comments: m.Loading(generation)),
          notice: None,
        )
      #(model, [FetchComments(story: story.id, generation:)])
    }
    m.Searching(m.Showing(m.SearchFound(query:, stories: _))) ->
      rerun_search(model, query, generation)
    m.Searching(m.Showing(m.SearchFailed(query:, error: _))) ->
      rerun_search(model, query, generation)
    m.Searching(_) -> #(model, [])
  }
}

fn rerun_search(
  model: m.Model,
  query: query.SearchQuery,
  generation: m.Generation,
) -> #(m.Model, List(Effect)) {
  let model =
    m.Model(
      ..model,
      generation:,
      screen: m.Searching(m.Showing(m.SearchInFlight(query:, generation:))),
      notice: None,
    )
  #(model, [SearchStories(query:, generation:)])
}

// Search

fn start_search(model: m.Model) -> #(m.Model, List(Effect)) {
  let previous = case model.screen {
    m.Searching(m.Showing(outcome)) -> Some(outcome)
    _ -> None
  }
  #(
    m.Model(
      ..model,
      screen: m.Searching(m.begin_search(previous)),
      notice: None,
    ),
    [],
  )
}

fn cancel_search(model: m.Model) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Editing(previous: Some(previous), ..)) -> #(
      m.Model(..model, screen: m.Searching(m.Showing(previous))),
      [],
    )
    m.Searching(_) -> #(m.Model(..model, screen: m.Browsing), [])
    _ -> #(model, [])
  }
}

fn submit_search(model: m.Model) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Editing(draft:, ..)) ->
      case query.parse(draft) {
        Error(_) -> #(model, [])
        Ok(search_query) -> {
          let generation = m.next_generation(model.generation)
          let model =
            m.Model(
              ..model,
              generation:,
              screen: m.Searching(
                m.Showing(m.SearchInFlight(query: search_query, generation:)),
              ),
              notice: None,
            )
          #(model, [SearchStories(query: search_query, generation:)])
        }
      }
    _ -> #(model, [])
  }
}

fn type_character(
  model: m.Model,
  character: String,
) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Editing(draft:, cursor:, previous:)) -> {
      let #(draft, cursor) = case string.length(draft) >= max_query_length {
        True -> #(draft, cursor)
        False -> insert_at(draft, cursor, character)
      }
      #(
        m.Model(
          ..model,
          screen: m.Searching(m.Editing(draft:, cursor:, previous:)),
        ),
        [],
      )
    }
    _ -> #(model, [])
  }
}

fn erase(model: m.Model) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Editing(draft:, cursor:, previous:)) -> {
      let #(draft, cursor) = delete_before(draft, cursor)
      #(
        m.Model(
          ..model,
          screen: m.Searching(m.Editing(draft:, cursor:, previous:)),
        ),
        [],
      )
    }
    _ -> #(model, [])
  }
}

fn delete_forward(model: m.Model) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Editing(draft:, cursor:, previous:)) -> {
      let draft = delete_at(draft, cursor)
      #(
        m.Model(
          ..model,
          screen: m.Searching(m.Editing(draft:, cursor:, previous:)),
        ),
        [],
      )
    }
    _ -> #(model, [])
  }
}

fn move_cursor(model: m.Model, by: Int) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Editing(draft:, cursor:, previous:)) -> {
      let cursor = int.clamp(cursor + by, 0, string.length(draft))
      #(
        m.Model(
          ..model,
          screen: m.Searching(m.Editing(draft:, cursor:, previous:)),
        ),
        [],
      )
    }
    _ -> #(model, [])
  }
}

fn move_cursor_to(model: m.Model, cursor: Int) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Editing(draft:, previous:, ..)) -> #(
      m.Model(
        ..model,
        screen: m.Searching(m.Editing(draft:, cursor:, previous:)),
      ),
      [],
    )
    _ -> #(model, [])
  }
}

fn move_cursor_to_end(model: m.Model) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Editing(draft:, ..)) ->
      move_cursor_to(model, string.length(draft))
    _ -> #(model, [])
  }
}

fn insert_at(draft: String, cursor: Int, character: String) -> #(String, Int) {
  let cursor = int.clamp(cursor, 0, string.length(draft))
  let before = string.slice(draft, 0, cursor)
  let after = string.slice(draft, cursor, string.length(draft) - cursor)
  #(before <> character <> after, cursor + string.length(character))
}

fn delete_before(draft: String, cursor: Int) -> #(String, Int) {
  case cursor <= 0 {
    True -> #(draft, 0)
    False -> {
      let before = string.slice(draft, 0, cursor - 1)
      let after = string.slice(draft, cursor, string.length(draft) - cursor)
      #(before <> after, cursor - 1)
    }
  }
}

fn delete_at(draft: String, cursor: Int) -> String {
  let cursor = int.clamp(cursor, 0, string.length(draft))
  let before = string.slice(draft, 0, cursor)
  let after = string.slice(draft, cursor + 1, string.length(draft) - cursor)
  before <> after
}

// Opening links

fn current_story(model: m.Model) -> Option(story.Story) {
  case model.screen {
    m.Browsing ->
      case model.stories {
        m.Loaded(items) -> listing.current(items)
        _ -> None
      }
    m.Searching(m.Showing(m.SearchFound(_, items))) -> listing.current(items)
    m.Searching(_) -> None
    m.Reading(story:, return_to: _, comments: _) -> Some(story)
  }
}

fn open_story(model: m.Model) -> #(m.Model, List(Effect)) {
  case current_story(model) {
    Some(found) -> #(model, [OpenUrl(story.link(found))])
    None -> #(model, [])
  }
}

fn open_comment(model: m.Model) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Reading(comments: m.Loaded(m.Comments(nav)), story: _, return_to: _) -> {
      let selected = zipper.current(nav.current)
      #(model, [OpenUrl(item_id.hn_url(selected.id))])
    }
    _ -> #(model, [])
  }
}

// Results of work done elsewhere

fn stories_loaded(
  model: m.Model,
  loaded_feed: feed.Feed,
  generation: m.Generation,
  result: Result(story.StoryBatch, error.AppError),
) -> #(m.Model, List(Effect)) {
  // Apply the result only while this feed is still loading the same generation.
  case model.stories {
    m.Loading(expected) ->
      case
        m.same_generation(generation, expected) && loaded_feed == model.feed
      {
        False -> #(model, [])
        True ->
          case result {
            Error(problem) -> #(
              m.Model(..model, stories: m.Failed(problem)),
              [],
            )
            Ok(batch) -> {
              let notice = case batch.failed > 0 {
                True ->
                  Some(
                    int.to_string(batch.failed)
                    <> plural(batch.failed, " story", " stories")
                    <> " couldn't be loaded",
                  )
                False -> None
              }
              #(
                m.Model(
                  ..model,
                  stories: m.Loaded(listing.from_list(batch.stories)),
                  notice: notice,
                ),
                [],
              )
            }
          }
      }
    _ -> #(model, [])
  }
}

fn comments_loaded(
  model: m.Model,
  loaded_story: item_id.ItemId,
  generation: m.Generation,
  result: Result(#(List(comment.Comment), Int), error.AppError),
) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Reading(story:, return_to:, comments: m.Loading(expected)) -> {
      case story.id == loaded_story && m.same_generation(generation, expected) {
        False -> #(model, [])
        True ->
          case result {
            Error(problem) -> #(
              m.Model(
                ..model,
                screen: m.Reading(
                  story:,
                  return_to:,
                  comments: m.Failed(problem),
                ),
              ),
              [],
            )
            Ok(#(comments, failed)) -> {
              let tree = m.comment_nav_from(listing.from_list(comments))
              let notice = case failed > 0 {
                True ->
                  Some(
                    int.to_string(failed)
                    <> plural(failed, " comment", " comments")
                    <> " couldn't be loaded",
                  )
                False -> None
              }
              let model =
                m.Model(
                  ..model,
                  screen: m.Reading(
                    story:,
                    return_to:,
                    comments: m.Loaded(tree),
                  ),
                  notice: notice,
                )
              #(model, [])
            }
          }
      }
    }
    _ -> #(model, [])
  }
}

fn search_loaded(
  model: m.Model,
  generation: m.Generation,
  result: Result(List(story.Story), error.AppError),
) -> #(m.Model, List(Effect)) {
  case model.screen {
    m.Searching(m.Showing(m.SearchInFlight(query:, generation: expected))) ->
      case m.same_generation(generation, expected) {
        False -> #(model, [])
        True -> {
          let outcome = case result {
            Error(problem) -> m.SearchFailed(query:, error: problem)
            Ok(stories) ->
              m.SearchFound(query:, stories: listing.from_list(stories))
          }
          #(m.Model(..model, screen: m.Searching(m.Showing(outcome))), [])
        }
      }
    _ -> #(model, [])
  }
}

fn browser_result(
  model: m.Model,
  result: Result(Nil, error.AppError),
) -> #(m.Model, List(Effect)) {
  case result {
    Ok(_) -> #(model, [])
    Error(problem) -> #(
      m.Model(..model, notice: Some(error.describe(problem))),
      [],
    )
  }
}

fn option_or(value: Option(a), fallback: a) -> a {
  case value {
    Some(inner) -> inner
    None -> fallback
  }
}

/// Singular or plural, chosen by the count.
fn plural(count: Int, one: String, many: String) -> String {
  case count == 1 {
    True -> one
    False -> many
  }
}
