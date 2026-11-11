import gleam/list
import gleam/option.{None, Some}
import gleam/time/timestamp
import gleeunit/should
import hngleam/app/keymap
import hngleam/app/model as m
import hngleam/app/msg.{
  Back, CancelSearch, CursorEnd, CursorHome, CursorLeft, CursorRight,
  DeleteForward, Erase, Next, NextFeed, OpenComment, OpenDetail, Previous, Quit,
  Reload, SelectFeed, StartSearch, SubmitSearch, Typed,
}
import hngleam/domain/feed
import hngleam/domain/item_id
import hngleam/domain/listing
import hngleam/domain/query
import hngleam/domain/story.{type Story, Story}
import hngleam/domain/terminal_size
import shore/key

pub fn browsing_binds_navigation_test() {
  let bindings = keymap.for_model(base_model())
  has(bindings, key.Char("j"), Next) |> should.be_true()
  has(bindings, key.Down, Next) |> should.be_true()
  has(bindings, key.Char("k"), Previous) |> should.be_true()
  has(bindings, key.Up, Previous) |> should.be_true()
  has(bindings, key.Char("l"), OpenDetail) |> should.be_true()
  has(bindings, key.Enter, OpenDetail) |> should.be_true()
}

pub fn browsing_binds_the_feed_keys_test() {
  let bindings = keymap.for_model(base_model())
  has(bindings, key.Tab, NextFeed) |> should.be_true()
  has(bindings, key.Char("1"), SelectFeed(feed.Top)) |> should.be_true()
  has(bindings, key.Char("5"), SelectFeed(feed.Show)) |> should.be_true()
  has(bindings, key.Char("/"), StartSearch) |> should.be_true()
  has(bindings, key.Char("r"), Reload) |> should.be_true()
  has(bindings, key.Char("q"), Quit) |> should.be_true()
  has(bindings, key.Esc, Quit) |> should.be_true()
}

pub fn reading_binds_comment_keys_test() {
  let bindings = keymap.for_model(reading_model())
  has(bindings, key.Char("h"), Back) |> should.be_true()
  has(bindings, key.Left, Back) |> should.be_true()
  has(bindings, key.Char("c"), OpenComment) |> should.be_true()
  has(bindings, key.Char("l"), OpenDetail) |> should.be_true()
}

pub fn reading_binds_the_feed_keys_test() {
  let bindings = keymap.for_model(reading_model())
  has(bindings, key.Char("1"), SelectFeed(feed.Top)) |> should.be_true()
  has(bindings, key.Char("2"), SelectFeed(feed.New)) |> should.be_true()
  has(bindings, key.Char("5"), SelectFeed(feed.Show)) |> should.be_true()
  has(bindings, key.Tab, NextFeed) |> should.be_false()
}

pub fn typing_binds_printable_characters_test() {
  let bindings = keymap.for_model(editing_model())
  has(bindings, key.Char("a"), Typed("a")) |> should.be_true()
  has(bindings, key.Char("q"), Typed("q")) |> should.be_true()
  has(bindings, key.Char(" "), Typed(" ")) |> should.be_true()
  has(bindings, key.Backspace, Erase) |> should.be_true()
  has(bindings, key.Enter, SubmitSearch) |> should.be_true()
  has(bindings, key.Esc, CancelSearch) |> should.be_true()
}

pub fn q_is_text_while_typing_but_quits_elsewhere_test() {
  has(keymap.for_model(editing_model()), key.Char("q"), Quit)
  |> should.be_false()

  has(keymap.for_model(base_model()), key.Char("q"), Quit)
  |> should.be_true()
}

pub fn results_bind_escape_to_cancel_test() {
  has(keymap.for_model(results_model()), key.Esc, CancelSearch)
  |> should.be_true()
  has(keymap.for_model(results_model()), key.Char("/"), StartSearch)
  |> should.be_true()
}

pub fn results_bind_reload_test() {
  has(keymap.for_model(results_model()), key.Char("r"), Reload)
  |> should.be_true()
}

pub fn editing_binds_cursor_keys_test() {
  let bindings = keymap.for_model(editing_model())
  has(bindings, key.Left, CursorLeft) |> should.be_true()
  has(bindings, key.Right, CursorRight) |> should.be_true()
  has(bindings, key.Home, CursorHome) |> should.be_true()
  has(bindings, key.End, CursorEnd) |> should.be_true()
  has(bindings, key.Delete, DeleteForward) |> should.be_true()
  has(bindings, key.Char("é"), Typed("é")) |> should.be_true()
}

pub fn ctrl_c_quits_test() {
  has(keymap.for_model(base_model()), key.Ctrl("C"), Quit) |> should.be_true()
  has(keymap.for_model(reading_model()), key.Ctrl("C"), Quit)
  |> should.be_true()
  has(keymap.for_model(results_model()), key.Ctrl("C"), Quit)
  |> should.be_true()
  has(keymap.for_model(editing_model()), key.Ctrl("C"), Quit)
  |> should.be_true()
}

fn has(bindings: List(#(key.Key, a)), pressed: key.Key, action: a) -> Bool {
  bindings |> list.contains(#(pressed, action))
}

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

fn a_story(value: Int) -> Story {
  Story(
    id: id_of(value),
    title: "story",
    url: None,
    author: Some("someone"),
    score: 1,
    posted_at: now(),
    comment_count: 0,
  )
}

fn base_model() -> m.Model {
  m.Model(
    feed: feed.Top,
    stories: m.Loaded(listing.from_list([a_story(1)])),
    screen: m.Browsing,
    generation: m.first_generation(),
    size: size(),
    now: now(),
    notice: None,
  )
}

fn reading_model() -> m.Model {
  m.Model(
    ..base_model(),
    screen: m.Reading(
      story: a_story(9),
      return_to: m.BackToFeed,
      comments: m.Loading(m.first_generation()),
    ),
  )
}

fn editing_model() -> m.Model {
  m.Model(
    ..base_model(),
    screen: m.Searching(m.Editing(draft: "", cursor: 0, previous: None)),
  )
}

fn results_model() -> m.Model {
  m.Model(
    ..base_model(),
    screen: m.Searching(
      m.Showing(m.SearchFound(
        query: query_of("gleam"),
        stories: listing.from_list([a_story(3)]),
      )),
    ),
  )
}

fn query_of(value: String) -> query.SearchQuery {
  case query.parse(value) {
    Ok(parsed) -> parsed
    Error(_) -> panic as "invalid query"
  }
}
