import gleam/list
import gleam/option.{None, Some}
import gleam/time/timestamp
import gleeunit/should
import hngleam/app/effect.{
  ExitApp, FetchComments, FetchFeed, OpenUrl, ScheduleTick, SearchStories,
}
import hngleam/app/error.{BrowserUnavailable, Timeout}
import hngleam/app/model as m
import hngleam/app/msg.{
  Back, BrowserResult, CancelSearch, CommentsLoaded, CursorEnd, CursorHome,
  CursorLeft, CursorRight, DeleteForward, Erase, Next, OpenComment, OpenDetail,
  OpenStory, Pressed, Previous, Quit, Reload, SearchLoaded, SelectFeed,
  StartSearch, StoriesLoaded, SubmitSearch, Typed,
}
import hngleam/app/update
import hngleam/domain/comment.{type Comment, Comment}
import hngleam/domain/feed
import hngleam/domain/item_id
import hngleam/domain/listing
import hngleam/domain/query
import hngleam/domain/story.{type Story, Story, StoryBatch}
import hngleam/domain/terminal_size
import hngleam/domain/zipper

pub fn init_loads_the_top_feed_and_starts_the_clock_test() {
  let #(model, effects) = update.init(size(), now())
  model.feed |> should.equal(feed.Top)
  model.screen |> should.equal(m.Browsing)
  model.stories |> should.equal(m.Loading(model.generation))
  effects
  |> should.equal([
    FetchFeed(feed: feed.Top, generation: model.generation),
    ScheduleTick(after_ms: update.tick_ms),
  ])
}

pub fn moving_down_selects_the_next_story_test() {
  let #(model, _) = update.update(base_model(), Pressed(Next))
  selected_index(model) |> should.equal(1)
}

pub fn moving_up_at_the_top_stays_put_test() {
  let #(model, _) = update.update(base_model(), Pressed(Previous))
  selected_index(model) |> should.equal(0)
}

pub fn quitting_asks_the_shell_to_exit_test() {
  let #(_model, effects) = update.update(base_model(), Pressed(Quit))
  effects |> should.equal([ExitApp])
}

pub fn opening_a_story_fetches_its_comments_test() {
  let model = base_model()
  let #(next, effects) = update.update(model, Pressed(OpenDetail))
  let expected_generation = m.next_generation(model.generation)

  next.generation |> should.equal(expected_generation)
  case next.screen {
    m.Reading(story:, comments:, ..) -> {
      story.id |> should.equal(first_story_id())
      comments |> should.equal(m.Loading(expected_generation))
    }
    _ -> panic as "expected the reading screen"
  }
  effects
  |> should.equal([
    FetchComments(story: first_story_id(), generation: expected_generation),
  ])
}

pub fn stale_feed_results_are_ignored_test() {
  let model = base_model()
  let stale = m.first_generation()
  let #(next, effects) =
    update.update(
      m.Model(..model, generation: m.next_generation(stale)),
      StoriesLoaded(
        feed: feed.Top,
        generation: stale,
        result: Ok(StoryBatch(stories: [], failed: 0)),
      ),
    )
  next.stories |> should.equal(model.stories)
  effects |> should.equal([])
}

pub fn a_failed_feed_shows_the_error_test() {
  let model = loading_model()
  let #(next, _) =
    update.update(
      model,
      StoriesLoaded(
        feed: feed.Top,
        generation: model.generation,
        result: Error(Timeout),
      ),
    )
  next.stories |> should.equal(m.Failed(Timeout))
}

pub fn reloading_from_a_failure_starts_a_new_fetch_test() {
  let model = loading_model()
  let #(failed, _) =
    update.update(
      model,
      StoriesLoaded(
        feed: feed.Top,
        generation: model.generation,
        result: Error(Timeout),
      ),
    )
  let #(next, effects) = update.update(failed, Pressed(Reload))

  next.stories |> should.equal(m.Loading(next.generation))
  effects
  |> should.equal([FetchFeed(feed: feed.Top, generation: next.generation)])
}

pub fn tab_switches_to_the_next_feed_test() {
  let #(next, effects) =
    update.update(base_model(), Pressed(SelectFeed(feed.New)))
  next.feed |> should.equal(feed.New)
  next.stories |> should.equal(m.Loading(next.generation))
  effects
  |> should.equal([FetchFeed(feed: feed.New, generation: next.generation)])
}

pub fn a_feed_key_leaves_a_nested_comment_test() {
  let #(drilled, _) = update.update(reading_model(), Pressed(OpenDetail))
  let #(next, effects) = update.update(drilled, Pressed(SelectFeed(feed.New)))

  next.screen |> should.equal(m.Browsing)
  next.feed |> should.equal(feed.New)
  next.stories |> should.equal(m.Loading(next.generation))
  effects
  |> should.equal([FetchFeed(feed: feed.New, generation: next.generation)])
}

pub fn the_current_feed_key_returns_from_a_story_to_its_list_test() {
  let #(next, effects) =
    update.update(reading_model(), Pressed(SelectFeed(feed.Top)))

  next.screen |> should.equal(m.Browsing)
  next.feed |> should.equal(feed.Top)
  next.stories |> should.equal(m.Loading(next.generation))
  effects
  |> should.equal([FetchFeed(feed: feed.Top, generation: next.generation)])
}

pub fn selecting_the_current_feed_does_nothing_test() {
  let model = base_model()
  let #(next, effects) = update.update(model, Pressed(SelectFeed(feed.Top)))
  next |> should.equal(model)
  effects |> should.equal([])
}

pub fn a_feed_with_no_stories_shows_the_empty_message_test() {
  let #(next, _) =
    update.update(
      loading_model(),
      StoriesLoaded(
        feed: feed.Top,
        generation: m.first_generation(),
        result: Ok(StoryBatch(stories: [], failed: 0)),
      ),
    )
  next.stories |> should.equal(m.Loaded(listing.Empty))
}

pub fn drilling_into_a_comment_keeps_the_parent_context_test() {
  let model = reading_model()
  let #(next, _) = update.update(model, Pressed(OpenDetail))

  case next.screen {
    m.Reading(comments: m.Loaded(m.Comments(nav)), ..) -> {
      m.comment_depth(nav) |> should.equal(2)
      nav.trail |> list.length() |> should.equal(1)
      zipper.current(nav.current).text |> should.equal("reply")
    }
    _ -> panic as "expected to drill into the replies"
  }
}

pub fn drilling_into_a_comment_without_replies_does_nothing_test() {
  let model = reading_model_without_replies()
  let #(next, effects) = update.update(model, Pressed(OpenDetail))
  next |> should.equal(model)
  effects |> should.equal([])
}

pub fn going_back_restores_the_parent_level_test() {
  let model = reading_model()
  let #(drilled, _) = update.update(model, Pressed(OpenDetail))
  let #(back, _) = update.update(drilled, Pressed(Back))

  case back.screen {
    m.Reading(comments: m.Loaded(m.Comments(nav)), ..) -> {
      m.comment_depth(nav) |> should.equal(1)
      zipper.current(nav.current).text |> should.equal("root")
    }
    _ -> panic as "expected to be back at the root"
  }
}

pub fn going_back_at_the_root_returns_to_the_list_test() {
  let model = reading_model()
  let #(back, _) = update.update(model, Pressed(Back))
  back.screen |> should.equal(m.Browsing)
}

pub fn tab_starts_a_search_test() {
  let #(next, _) = update.update(base_model(), Pressed(StartSearch))
  next.screen
  |> should.equal(m.Searching(m.Editing(draft: "", cursor: 0, previous: None)))
}

pub fn typing_edits_the_search_draft_test() {
  let #(searching, _) = update.update(base_model(), Pressed(StartSearch))
  let #(typed, _) = update.update(searching, Pressed(Typed("g")))
  let #(typed, _) = update.update(typed, Pressed(Typed("o")))
  let #(typed, _) = update.update(typed, Pressed(Erase))

  case typed.screen {
    m.Searching(m.Editing(draft:, ..)) -> draft |> should.equal("g")
    _ -> panic as "expected an editing search"
  }
}

pub fn submitting_a_search_starts_a_query_test() {
  let #(searching, _) = update.update(base_model(), Pressed(StartSearch))
  let #(typed, _) = update.update(searching, Pressed(Typed("g")))
  let #(submitted, effects) = update.update(typed, Pressed(SubmitSearch))

  case submitted.screen {
    m.Searching(m.Showing(m.SearchInFlight(query:, generation:))) -> {
      query.to_string(query) |> should.equal("g")
      generation |> should.equal(submitted.generation)
    }
    _ -> panic as "expected a search in flight"
  }
  { effects != [] } |> should.be_true()
}

pub fn an_empty_search_is_not_submitted_test() {
  let #(searching, _) = update.update(base_model(), Pressed(StartSearch))
  let #(submitted, effects) = update.update(searching, Pressed(SubmitSearch))
  submitted |> should.equal(searching)
  effects |> should.equal([])
}

pub fn cancelling_a_search_returns_to_the_list_test() {
  let #(searching, _) = update.update(base_model(), Pressed(StartSearch))
  let #(cancelled, _) = update.update(searching, Pressed(CancelSearch))
  cancelled.screen |> should.equal(m.Browsing)
}

pub fn stale_search_results_are_ignored_test() {
  let #(searching, _) = update.update(base_model(), Pressed(StartSearch))
  let #(typed, _) = update.update(searching, Pressed(Typed("g")))
  let #(submitted, _) = update.update(typed, Pressed(SubmitSearch))

  let #(after, _) =
    update.update(
      submitted,
      SearchLoaded(
        generation: m.first_generation(),
        result: Ok([a_story(30, "stale")]),
      ),
    )
  after.screen |> should.equal(submitted.screen)
}

pub fn search_results_are_shown_test() {
  let #(searching, _) = update.update(base_model(), Pressed(StartSearch))
  let #(typed, _) = update.update(searching, Pressed(Typed("g")))
  let #(submitted, _) = update.update(typed, Pressed(SubmitSearch))
  let #(after, _) =
    update.update(
      submitted,
      SearchLoaded(
        generation: submitted.generation,
        result: Ok([a_story(30, "result")]),
      ),
    )

  case after.screen {
    m.Searching(m.Showing(m.SearchFound(stories:, query: _))) ->
      listing.length(stories) |> should.equal(1)
    _ -> panic as "expected search results"
  }
}

pub fn a_browser_failure_becomes_a_notice_test() {
  let #(next, _) =
    update.update(
      base_model(),
      BrowserResult(result: Error(BrowserUnavailable(command: "xdg-open"))),
    )
  next.notice |> should.be_some()
}

pub fn opening_a_story_asks_the_shell_to_open_its_url_test() {
  let model =
    m.Model(
      ..base_model(),
      stories: m.Loaded(
        listing.from_list([a_story_with_url(1, "https://example.com/x")]),
      ),
    )
  let #(_next, effects) = update.update(model, Pressed(OpenStory))
  effects |> should.equal([OpenUrl("https://example.com/x")])
}

pub fn a_story_without_a_url_opens_its_hn_page_test() {
  let #(_next, effects) = update.update(base_model(), Pressed(OpenStory))
  effects
  |> should.equal([OpenUrl("https://news.ycombinator.com/item?id=1")])
}

pub fn a_search_does_not_drop_an_in_flight_feed_test() {
  let model = m.Model(..base_model(), stories: m.Loading(m.first_generation()))
  let #(searching, _) = update.update(model, Pressed(StartSearch))
  let #(typed, _) = update.update(searching, Pressed(Typed("g")))
  let #(submitted, _) = update.update(typed, Pressed(SubmitSearch))

  submitted.stories |> should.equal(m.Loading(m.first_generation()))
  let #(next, _) =
    update.update(
      submitted,
      StoriesLoaded(
        feed: feed.Top,
        generation: m.first_generation(),
        result: Ok(StoryBatch(stories: [a_story(1, "kept")], failed: 0)),
      ),
    )
  next.stories
  |> should.equal(m.Loaded(listing.from_list([a_story(1, "kept")])))
}

pub fn switching_feeds_ignores_the_previous_generation_test() {
  let model = m.Model(..base_model(), stories: m.Loading(m.first_generation()))
  let #(switched, _) = update.update(model, Pressed(SelectFeed(feed.New)))
  let #(next, _) =
    update.update(
      switched,
      StoriesLoaded(
        feed: feed.Top,
        generation: m.first_generation(),
        result: Ok(StoryBatch(stories: [a_story(9, "old")], failed: 0)),
      ),
    )
  next.stories |> should.equal(switched.stories)
}

pub fn escape_while_editing_restores_the_previous_results_test() {
  let found =
    m.SearchFound(
      query: query_of("gleam"),
      stories: listing.from_list([a_story(3, "hit")]),
    )
  let model = m.Model(..base_model(), screen: m.Searching(m.Showing(found)))
  let #(editing, _) = update.update(model, Pressed(StartSearch))
  let #(restored, _) = update.update(editing, Pressed(CancelSearch))
  restored.screen |> should.equal(m.Searching(m.Showing(found)))
}

pub fn reloading_a_failed_search_retries_the_query_test() {
  let parsed = query_of("gleam")
  let model =
    m.Model(
      ..base_model(),
      screen: m.Searching(
        m.Showing(m.SearchFailed(query: parsed, error: Timeout)),
      ),
    )
  let #(next, effects) = update.update(model, Pressed(Reload))
  case next.screen {
    m.Searching(m.Showing(m.SearchInFlight(query:, generation:))) -> {
      query.to_string(query) |> should.equal("gleam")
      generation |> should.equal(next.generation)
    }
    _ -> panic as "expected the search to be in flight again"
  }
  effects
  |> should.equal([SearchStories(query: parsed, generation: next.generation)])
}

pub fn the_search_cursor_edits_in_place_test() {
  let #(searching, _) = update.update(base_model(), Pressed(StartSearch))
  let #(typed, _) = update.update(searching, Pressed(Typed("g")))
  let #(typed, _) = update.update(typed, Pressed(Typed("o")))
  let #(moved, _) = update.update(typed, Pressed(CursorLeft))
  let #(typed, _) = update.update(moved, Pressed(Typed("x")))
  let #(home, _) = update.update(typed, Pressed(CursorHome))
  let #(deleted, _) = update.update(home, Pressed(DeleteForward))

  case deleted.screen {
    m.Searching(m.Editing(draft:, cursor:, ..)) -> {
      draft |> should.equal("xo")
      cursor |> should.equal(0)
    }
    _ -> panic as "expected an editing search"
  }
}

pub fn opening_the_selected_comment_uses_its_hn_page_test() {
  let #(_next, effects) = update.update(reading_model(), Pressed(OpenComment))
  effects
  |> should.equal([OpenUrl("https://news.ycombinator.com/item?id=1")])
}

pub fn a_loaded_comment_thread_replaces_the_loading_state_test() {
  let model = awaiting_comments()
  let #(next, effects) =
    update.update(
      model,
      CommentsLoaded(
        story: id_of(9),
        generation: model.generation,
        result: Ok(#([a_comment(11, "hello", [])], 0)),
      ),
    )
  effects |> should.equal([])
  next.notice |> should.equal(None)
  selected_comment_id(next) |> should.equal(11)
}

pub fn an_empty_comment_thread_is_shown_as_no_comments_test() {
  let model = awaiting_comments()
  let #(next, _) =
    update.update(
      model,
      CommentsLoaded(
        story: id_of(9),
        generation: model.generation,
        result: Ok(#([], 0)),
      ),
    )
  case next.screen {
    m.Reading(comments: m.Loaded(m.NoComments), ..) -> Nil
    _ -> panic as "expected no comments"
  }
}

pub fn a_failed_comment_fetch_is_shown_test() {
  let model = awaiting_comments()
  let #(next, _) =
    update.update(
      model,
      CommentsLoaded(
        story: id_of(9),
        generation: model.generation,
        result: Error(Timeout),
      ),
    )
  case next.screen {
    m.Reading(comments:, ..) -> comments |> should.equal(m.Failed(Timeout))
    _ -> panic as "expected the reading screen"
  }
}

pub fn a_stale_comment_thread_is_ignored_test() {
  let model = awaiting_comments()
  let #(next, effects) =
    update.update(
      model,
      CommentsLoaded(
        story: id_of(9),
        generation: m.next_generation(model.generation),
        result: Ok(#([a_comment(11, "late", [])], 0)),
      ),
    )
  next.screen |> should.equal(model.screen)
  effects |> should.equal([])
}

pub fn comments_for_another_story_are_ignored_test() {
  let model = awaiting_comments()
  let #(next, effects) =
    update.update(
      model,
      CommentsLoaded(
        story: id_of(4),
        generation: model.generation,
        result: Ok(#([a_comment(11, "other", [])], 0)),
      ),
    )
  next.screen |> should.equal(model.screen)
  effects |> should.equal([])
}

pub fn a_comment_failure_count_is_reported_test() {
  let model = awaiting_comments()
  let #(one, _) =
    update.update(
      model,
      CommentsLoaded(
        story: id_of(9),
        generation: model.generation,
        result: Ok(#([a_comment(11, "hello", [])], 1)),
      ),
    )
  one.notice |> should.equal(Some("1 comment couldn't be loaded"))

  let #(many, _) =
    update.update(
      model,
      CommentsLoaded(
        story: id_of(9),
        generation: model.generation,
        result: Ok(#([a_comment(11, "hello", [])], 2)),
      ),
    )
  many.notice |> should.equal(Some("2 comments couldn't be loaded"))
}

pub fn comments_that_arrive_after_the_thread_loaded_are_ignored_test() {
  let model = reading_model()
  let #(next, effects) =
    update.update(
      model,
      CommentsLoaded(
        story: id_of(9),
        generation: model.generation,
        result: Error(Timeout),
      ),
    )
  next.screen |> should.equal(model.screen)
  effects |> should.equal([])
}

pub fn moving_down_selects_the_next_comment_test() {
  let model = m.Model(..two_comments(), notice: Some("earlier"))
  let #(next, _) = update.update(model, Pressed(Next))
  selected_comment_id(next) |> should.equal(2)
  next.notice |> should.equal(None)
}

pub fn moving_up_on_the_first_comment_stays_put_test() {
  let #(next, _) = update.update(two_comments(), Pressed(Previous))
  selected_comment_id(next) |> should.equal(1)
}

pub fn moving_through_comments_that_are_still_loading_does_nothing_test() {
  let model = awaiting_comments()
  let #(next, _) = update.update(model, Pressed(Next))
  next.screen |> should.equal(model.screen)
}

pub fn moving_down_selects_the_next_search_result_test() {
  let found =
    m.SearchFound(
      query: query_of("gleam"),
      stories: listing.from_list([a_story(3, "one"), a_story(4, "two")]),
    )
  let model =
    m.Model(
      ..base_model(),
      notice: Some("earlier"),
      screen: m.Searching(m.Showing(found)),
    )
  let #(next, _) = update.update(model, Pressed(Next))
  next.notice |> should.equal(None)
  case next.screen {
    m.Searching(m.Showing(m.SearchFound(stories:, ..))) ->
      listing.index(stories) |> should.equal(Some(1))
    _ -> panic as "expected search results"
  }
}

pub fn moving_while_editing_a_search_leaves_the_draft_test() {
  let screen = m.Searching(m.Editing(draft: "go", cursor: 1, previous: None))
  let model = m.Model(..base_model(), screen:)
  let #(next, _) = update.update(model, Pressed(Next))
  next.screen |> should.equal(screen)
}

pub fn end_moves_the_search_cursor_to_the_end_test() {
  let model =
    m.Model(
      ..base_model(),
      screen: m.Searching(m.Editing(draft: "go", cursor: 0, previous: None)),
    )
  let #(next, _) = update.update(model, Pressed(CursorEnd))
  case next.screen {
    m.Searching(m.Editing(draft:, cursor:, ..)) -> {
      draft |> should.equal("go")
      cursor |> should.equal(2)
    }
    _ -> panic as "expected an editing search"
  }
}

pub fn right_moves_the_search_cursor_one_character_test() {
  let model =
    m.Model(
      ..base_model(),
      screen: m.Searching(m.Editing(draft: "go", cursor: 0, previous: None)),
    )
  let #(next, _) = update.update(model, Pressed(CursorRight))
  case next.screen {
    m.Searching(m.Editing(cursor:, ..)) -> cursor |> should.equal(1)
    _ -> panic as "expected an editing search"
  }
}

// Fixtures

fn size() -> terminal_size.TerminalSize {
  terminal_size.make(110, 40)
}

fn now() -> timestamp.Timestamp {
  timestamp.from_unix_seconds(1_700_000_000)
}

fn id_of(value: Int) -> item_id.ItemId {
  case item_id.item_id(value) {
    Ok(id) -> id
    Error(_) -> panic as "invalid id"
  }
}

fn a_story_with_url(value: Int, url: String) -> Story {
  Story(..a_story(value, "with a link"), url: Some(url))
}

fn a_story(value: Int, title: String) -> Story {
  Story(
    id: id_of(value),
    title: title,
    url: None,
    author: Some("someone"),
    score: 10,
    posted_at: now(),
    comment_count: 2,
  )
}

fn first_story_id() -> item_id.ItemId {
  id_of(1)
}

fn query_of(value: String) -> query.SearchQuery {
  case query.parse(value) {
    Ok(parsed) -> parsed
    Error(_) -> panic as "invalid query"
  }
}

fn loading_model() -> m.Model {
  m.Model(..base_model(), stories: m.Loading(m.first_generation()))
}

fn base_model() -> m.Model {
  m.Model(
    feed: feed.Top,
    stories: m.Loaded(listing.from_list([a_story(1, "one"), a_story(2, "two")])),
    screen: m.Browsing,
    generation: m.first_generation(),
    size: size(),
    now: now(),
    notice: None,
  )
}

fn selected_index(model: m.Model) -> Int {
  case model.stories {
    m.Loaded(items) ->
      case listing.index(items) {
        Some(index) -> index
        None -> -1
      }
    _ -> -1
  }
}

fn a_comment(value: Int, text: String, replies: List(Comment)) -> Comment {
  Comment(
    id: id_of(value),
    author: Some("author"),
    text: text,
    posted_at: now(),
    replies: replies,
  )
}

fn nav_of(comments: List(Comment)) -> m.CommentNav {
  case zipper.from_list(comments) {
    Ok(current) -> m.CommentNav(current:, trail: [])
    Error(_) -> panic as "expected comments"
  }
}

fn awaiting_comments() -> m.Model {
  m.Model(
    ..base_model(),
    screen: m.Reading(
      story: a_story(9, "story"),
      return_to: m.BackToFeed,
      comments: m.Loading(m.first_generation()),
    ),
  )
}

fn two_comments() -> m.Model {
  m.Model(
    ..base_model(),
    screen: m.Reading(
      story: a_story(9, "story"),
      return_to: m.BackToFeed,
      comments: m.Loaded(
        m.Comments(
          nav_of([a_comment(1, "first", []), a_comment(2, "second", [])]),
        ),
      ),
    ),
  )
}

fn selected_comment_id(model: m.Model) -> Int {
  case model.screen {
    m.Reading(comments: m.Loaded(m.Comments(nav)), ..) ->
      item_id.to_int(m.selected_comment(nav).id)
    _ -> panic as "expected a selected comment"
  }
}

fn reading_model() -> m.Model {
  let child = a_comment(2, "reply", [])
  let root = a_comment(1, "root", [child])
  m.Model(
    ..base_model(),
    screen: m.Reading(
      story: a_story(9, "story"),
      return_to: m.BackToFeed,
      comments: m.Loaded(m.Comments(nav_of([root]))),
    ),
  )
}

fn reading_model_without_replies() -> m.Model {
  m.Model(
    ..base_model(),
    screen: m.Reading(
      story: a_story(9, "story"),
      return_to: m.BackToFeed,
      comments: m.Loaded(m.Comments(nav_of([a_comment(1, "root", [])]))),
    ),
  )
}
