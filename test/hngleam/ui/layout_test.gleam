//// Golden tests for the layout. Each snapshot records both the text and the
//// style of every line, so a change in padding, truncation or emphasis is
//// visible in review.

import birdie
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import gleeunit/should
import hngleam/app/error.{Timeout}
import hngleam/app/model as m
import hngleam/domain/comment.{type Comment, Comment}
import hngleam/domain/feed
import hngleam/domain/item_id
import hngleam/domain/listing
import hngleam/domain/query
import hngleam/domain/story.{type Story, Story}
import hngleam/domain/terminal_size
import hngleam/domain/zipper
import hngleam/ui/layout

pub fn story_list_loading_test() {
  let model = base_model(80, 24)
  birdie.snap(content: render(model), title: "story list loading")
}

pub fn story_list_loaded_test() {
  let model =
    base_model(80, 24)
    |> with_stories([
      a_story(1, "A small story about terminals", 260, 93, 3600),
      a_story(
        2,
        "Another story with a rather long title that needs truncating",
        48,
        8,
        7200,
      ),
      a_story(3, "Ask HN: What are you working on?", 12, 0, 60),
    ])

  birdie.snap(content: render(model), title: "story list loaded")
}

pub fn story_list_empty_test() {
  let model = m.Model(..base_model(80, 24), stories: m.Loaded(listing.Empty))
  birdie.snap(content: render(model), title: "story list empty")
}

pub fn story_list_narrow_test() {
  // Below the minimum width the layout explains itself instead of drawing a
  // garbled frame.
  let model = base_model(40, 24)
  birdie.snap(content: render(model), title: "story list narrow")
}

pub fn feed_error_test() {
  let model = m.Model(..base_model(80, 24), stories: m.Failed(Timeout))
  birdie.snap(content: render(model), title: "feed error")
}

pub fn comments_error_test() {
  let model =
    base_model(80, 24)
    |> with_stories([a_story(1, "A story worth reading", 260, 93, 3600)])
    |> fn(model: m.Model) {
      m.Model(
        ..model,
        screen: m.Reading(
          story: a_story(1, "A story worth reading", 260, 93, 3600),
          return_to: m.BackToFeed,
          comments: m.Failed(Timeout),
        ),
      )
    }
  birdie.snap(content: render(model), title: "comments error")
}

pub fn notice_in_the_status_bar_test() {
  let nav =
    m.CommentNav(
      current: zipper_of([a_comment(100, "alice", "text", [])]),
      trail: [],
    )
  let model =
    base_model(80, 24)
    |> with_stories([a_story(1, "A story worth reading", 260, 93, 3600)])
    |> reading(a_story(1, "A story worth reading", 260, 93, 3600), nav)
    |> fn(model: m.Model) {
      m.Model(..model, notice: Some("1 comment couldn't be loaded"))
    }
  birdie.snap(content: render(model), title: "notice in the status bar")
}

pub fn detail_with_comments_test() {
  let comment =
    a_comment(100, "alice", "The comments are the best part of this site.", [])
  let second = a_comment(101, "bob", "I disagree, but politely.", [])

  let nav = m.CommentNav(current: zipper_of([comment, second]), trail: [])

  let model =
    base_model(80, 24)
    |> with_stories([a_story(1, "A story worth reading", 260, 93, 3600)])
    |> reading(a_story(1, "A story worth reading", 260, 93, 3600), nav)

  birdie.snap(content: render(model), title: "detail with comments")
}

pub fn detail_nested_test() {
  let reply = a_comment(101, "bob", "A reply that disagrees.", [])
  let root = a_comment(100, "alice", "The parent comment.", [reply])
  let nav =
    m.CommentNav(current: zipper_of([reply]), trail: [
      m.Crumb(level: zipper_of([root]), parent: root),
    ])

  let model =
    base_model(80, 24)
    |> with_stories([a_story(1, "A story worth reading", 260, 93, 3600)])
    |> reading(a_story(1, "A story worth reading", 260, 93, 3600), nav)

  birdie.snap(content: render(model), title: "detail nested")
}

pub fn search_editing_test() {
  let model =
    m.Model(
      ..base_model(80, 24),
      screen: m.Searching(m.Editing(draft: "gleam", cursor: 5, previous: None)),
    )
  birdie.snap(content: render(model), title: "search editing")
}

pub fn search_with_no_results_test() {
  let model =
    m.Model(
      ..base_model(80, 24),
      screen: m.Searching(
        m.Showing(m.SearchFound(query: query_of("zzzz"), stories: listing.Empty)),
      ),
    )
  birdie.snap(content: render(model), title: "search with no results")
}

pub fn a_tall_comment_stays_inside_the_frame_test() {
  let text = string.repeat("word ", 400)
  let comment = a_comment(1, "alice", text, [])
  let nav = m.CommentNav(current: zipper_of([comment]), trail: [])
  let height = 12
  let model =
    base_model(80, height)
    |> reading(a_story(1, "A story worth reading", 260, 93, 3600), nav)

  { list.length(layout.frame(model).lines) <= height } |> should.be_true()
}

pub fn search_results_test() {
  let model =
    m.Model(
      ..base_model(80, 24),
      screen: m.Searching(
        m.Showing(m.SearchFound(
          query: query_of("gleam"),
          stories: listing.from_list([
            a_story(
              4,
              "Gleam: a statically typed language for the Erlang VM",
              325,
              236,
              100_000,
            ),
          ]),
        )),
      ),
    )
  birdie.snap(content: render(model), title: "search results")
}

// Rendering

fn render(model: m.Model) -> String {
  layout.frame(model).lines
  |> list.map(fn(line) { style_tag(line.style) <> "|" <> line.text })
  |> string.join("\n")
}

fn style_tag(style: layout.LineStyle) -> String {
  case style {
    layout.Border -> "BORDER"
    layout.Title -> "TITLE "
    layout.TabActive -> "TABACT"
    layout.TabInactive -> "TAB   "
    layout.Selected -> "SELECT"
    layout.Meta -> "META  "
    layout.Error -> "ERROR "
    layout.Notice -> "NOTICE"
    layout.Hint -> "HINT  "
    layout.Plain -> "PLAIN "
  }
}

// Fixtures

fn now() -> timestamp.Timestamp {
  timestamp.from_unix_seconds(1_700_000_000)
}

fn id_of(value: Int) -> item_id.ItemId {
  case item_id.item_id(value) {
    Ok(id) -> id
    Error(_) -> panic as "invalid id"
  }
}

fn a_story(
  value: Int,
  title: String,
  score: Int,
  comments: Int,
  age_seconds: Int,
) -> Story {
  Story(
    id: id_of(value),
    title: title,
    url: Some("https://example.com/post"),
    author: Some("someone"),
    score: score,
    posted_at: timestamp.from_unix_seconds(1_700_000_000 - age_seconds),
    comment_count: comments,
  )
}

fn a_comment(
  value: Int,
  author: String,
  text: String,
  replies: List(Comment),
) -> Comment {
  Comment(
    id: id_of(value),
    author: Some(author),
    text:,
    posted_at: timestamp.from_unix_seconds(1_700_000_000 - 600),
    replies:,
  )
}

fn zipper_of(comments: List(Comment)) -> zipper.Zipper(Comment) {
  case zipper.from_list(comments) {
    Ok(value) -> value
    Error(_) -> panic as "expected comments"
  }
}

fn query_of(value: String) -> query.SearchQuery {
  case query.parse(value) {
    Ok(parsed) -> parsed
    Error(_) -> panic as "invalid query"
  }
}

fn base_model(width: Int, height: Int) -> m.Model {
  m.Model(
    feed: feed.Top,
    stories: m.Loading(m.first_generation()),
    screen: m.Browsing,
    generation: m.first_generation(),
    size: terminal_size.make(width, height),
    now: now(),
    notice: None,
  )
}

fn with_stories(model: m.Model, stories: List(Story)) -> m.Model {
  m.Model(..model, stories: m.Loaded(listing.from_list(stories)))
}

fn reading(model: m.Model, story: Story, nav: m.CommentNav) -> m.Model {
  m.Model(
    ..model,
    screen: m.Reading(
      story:,
      return_to: m.BackToFeed,
      comments: m.Loaded(m.Comments(nav)),
    ),
  )
}
