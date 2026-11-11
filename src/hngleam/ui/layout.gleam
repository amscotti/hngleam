//// Turning the model into a frame of pre-padded, single-style text lines.
////
//// Everything visual is decided here, and only here: the layout measures text,
//// truncates it, wraps it, decides which rows are visible, and pads every line
//// to an exact width. `ui/render` then does nothing but map styles to colours.
////
//// Keeping the canvas two columns narrower than the terminal leaves room for
//// shore's text node, which always clips to `width - 2`.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import hngleam/app/error
import hngleam/app/model as m
import hngleam/domain/comment.{type Comment, author_label, reply_label}
import hngleam/domain/feed
import hngleam/domain/listing
import hngleam/domain/query
import hngleam/domain/story.{type Story, shown_url}
import hngleam/domain/terminal_size
import hngleam/domain/zipper
import hngleam/text/relative_time
import hngleam/text/wrap
import hngleam/ui/viewport

/// What a line means, rather than what colour it is. `ui/render` owns the
/// mapping to the terminal's eight colours.
pub type LineStyle {
  Border
  Title
  TabActive
  TabInactive
  Selected
  Meta
  Error
  Notice
  Hint
  Plain
}

/// One row of the screen.
pub type Line {
  Line(text: String, style: LineStyle)
}

/// A complete screen.
pub type Frame {
  Frame(lines: List(Line))
}

const min_width: Int = 48

const min_height: Int = 12

const app_title: String = "Hacker News Explorer"

/// The narrowest canvas the layout is designed for.
pub fn minimum_width() -> Int {
  min_width
}

/// The shortest canvas the layout is designed for.
pub fn minimum_height() -> Int {
  min_height
}

/// Build the frame for the current state.
pub fn frame(model: m.Model) -> Frame {
  let width = terminal_size.width(model.size) - 2
  let height = terminal_size.height(model.size)

  case width < min_width || height < min_height {
    True -> {
      let message =
        "Terminal too small — make the window at least "
        <> int.to_string(min_width + 2)
        <> "x"
        <> int.to_string(min_height)
      Frame(
        lines: message
        |> wrap.wrap(int.max(width, 12))
        |> list.map(fn(text) { Line(text, Error) }),
      )
    }
    False -> {
      let inner = width - 4
      let body = body(model, inner, height - 6)
      let lines =
        list.append(
          [
            Line(top_border(width), Border),
            boxed(Line(tab_row(model, inner), Meta), inner),
            Line(divider(width), Border),
          ],
          list.append(list.map(body, fn(line) { boxed(line, inner) }), [
            boxed(Line(status_row(model, inner), status_style(model)), inner),
            Line(bottom_border(width), Border),
          ]),
        )
      Frame(lines:)
    }
  }
}

// Chrome

fn top_border(width: Int) -> String {
  let padding = width - 5 - string.length(app_title)
  "╭─ " <> app_title <> " " <> string.repeat("─", int.max(padding, 1)) <> "╮"
}

fn divider(width: Int) -> String {
  "├" <> string.repeat("─", int.max(width - 2, 1)) <> "┤"
}

fn bottom_border(width: Int) -> String {
  "╰" <> string.repeat("─", int.max(width - 2, 1)) <> "╯"
}

fn boxed(line: Line, inner: Int) -> Line {
  Line(text: "│ " <> wrap.fit(line.text, inner) <> " │", style: line.style)
}

fn tab_row(model: m.Model, inner: Int) -> String {
  let tabs =
    feed.all()
    |> list.map(fn(feed) {
      let label = feed.tab_label(feed)
      case feed == model.feed {
        True -> "[" <> label <> "]"
        False -> " " <> label <> " "
      }
    })
    |> string.join(" ")

  let search = case model.screen {
    m.Searching(_) -> "   [Search]"
    _ -> ""
  }
  wrap.fit(tabs <> search, inner)
}

fn status_style(model: m.Model) -> LineStyle {
  case model.notice {
    Some(_) -> Notice
    None -> Hint
  }
}

fn status_row(model: m.Model, inner: Int) -> String {
  let text = case model.notice {
    Some(notice) -> notice
    None -> hints(model)
  }
  wrap.fit(text, inner)
}

fn hints(model: m.Model) -> String {
  case model.screen {
    m.Browsing -> "j/k:Navigate  l/→:Detail  o:Open  /:Search  r:Reload  q:Quit"
    m.Reading(comments:, ..) ->
      case comments {
        m.Loaded(m.Comments(nav)) ->
          case nav.trail {
            [] ->
              "j/k:Navigate  l/→:Replies  o:Open  c:HN  h/←:Stories  1-5:Feeds  q:Quit"
            _ ->
              "j/k:Navigate  l/→:Replies  o:Open  c:HN  h/←:Back  1-5:Feeds  q:Quit"
          }
        _ -> "j/k:Navigate  o:Open  c:HN  h/←:Stories  1-5:Feeds  q:Quit"
      }
    m.Searching(m.Editing(..)) -> "Type to search  Enter:Search  Esc:Cancel"
    m.Searching(_) ->
      "j/k:Navigate  l/→:Detail  o:Open  /:Edit  r:Retry  Esc:Back  q:Quit"
  }
}

// Body

fn body(model: m.Model, inner: Int, rows: Int) -> List(Line) {
  case model.screen {
    m.Browsing -> browsing(model, inner, rows)
    m.Reading(story:, return_to:, comments:) ->
      reading(model, story, return_to, comments, inner, rows)
    m.Searching(m.Editing(draft:, cursor:, ..)) ->
      editing(draft, cursor, inner, rows)
    m.Searching(m.Showing(result)) -> search_outcome(model, result, inner, rows)
  }
}

fn browsing(model: m.Model, inner: Int, rows: Int) -> List(Line) {
  case model.stories {
    m.Loaded(items) ->
      case listing.is_empty(items) {
        True -> message("No stories found", rows)
        False -> story_panel(items, model.now, inner, rows)
      }
    m.Loading(_) -> message("Loading stories…", rows)
    m.NotAsked -> message("Press r to load stories", rows)
    m.Failed(problem) -> failure(problem, inner, rows)
  }
}

fn reading(
  model: m.Model,
  story: Story,
  return_to: m.ReturnTo,
  comments: m.Remote(m.CommentTree),
  inner: Int,
  rows: Int,
) -> List(Line) {
  let _ = return_to
  let header = story_header(story, model.now, inner)
  let remaining = int.max(rows - list.length(header), 1)

  let panel = case comments {
    m.Loaded(m.Comments(nav)) ->
      comments_panel(nav, model.now, inner, remaining)
    m.Loaded(m.NoComments) -> message("No comments yet", remaining)
    m.Loading(_) -> message("Loading comments…", remaining)
    m.NotAsked -> message("Press r to load comments", remaining)
    m.Failed(problem) -> failure(problem, inner, remaining)
  }

  list.append(header, panel)
}

fn story_header(story: Story, now: Timestamp, inner: Int) -> List(Line) {
  let titles =
    story.title
    |> wrap.wrap(inner)
    |> list.take(2)
    |> list.map(fn(text) { Line(text, Title) })

  let meta =
    int.to_string(story.score)
    <> " points | "
    <> story_author_label(story)
    <> " | "
    <> relative_time.relative(now:, then: story.posted_at)
    <> " | "
    <> int.to_string(story.comment_count)
    <> comment_word(story.comment_count)

  let url = case shown_url(story) {
    Some(link) -> [Line(wrap.truncate(link, inner), Meta)]
    None -> []
  }

  list.append(titles, [
    Line(wrap.fit(meta, inner), Meta),
    ..list.append(url, [Line(divider_line(inner), Border)])
  ])
}

fn divider_line(inner: Int) -> String {
  string.repeat("─", int.max(inner, 1))
}

fn comments_panel(
  nav: m.CommentNav,
  now: Timestamp,
  inner: Int,
  rows: Int,
) -> List(Line) {
  let context = case m.parent_comment(nav) {
    Some(parent) -> parent_context(parent, m.comment_depth(nav), inner)
    None -> []
  }
  let available = int.max(rows - list.length(context), 1)
  let items = zipper.to_list(nav.current)
  let selected_index = zipper.index(nav.current)
  let blocks = comment_blocks(items, selected_index, now, inner)
  let heights = list.map(blocks, fn(block) { block.1 })
  let #(start, end) = viewport.window(heights, selected_index, available)
  let visible =
    blocks
    |> list.drop(start)
    |> list.take(end - start)
    |> list.map(fn(block) { block.0 })
    |> list.flatten
    |> list.take(available)

  list.append(context, pad_lines(visible, available))
}

fn comment_blocks(
  items: List(Comment),
  selected: Int,
  now: Timestamp,
  inner: Int,
) -> List(#(List(Line), Int)) {
  items
  |> list.index_map(fn(comment, index) {
    let is_selected = index == selected
    let header = comment_header(comment, now, is_selected, inner)
    let body = comment_body(comment, inner)
    let block = list.append([header], list.append(body, [Line("", Plain)]))
    #(block, list.length(block))
  })
}

fn comment_header(
  comment: Comment,
  now: Timestamp,
  is_selected: Bool,
  inner: Int,
) -> Line {
  let marker = case is_selected {
    True -> "▌ "
    False -> "  "
  }
  let text =
    marker
    <> author_label(comment)
    <> "  "
    <> relative_time.relative(now:, then: comment.posted_at)
    <> "  "
    <> reply_label(comment)

  Line(wrap.fit(text, inner), case is_selected {
    True -> Selected
    False -> Meta
  })
}

fn comment_body(comment: Comment, inner: Int) -> List(Line) {
  let width = int.max(inner - 2, 8)
  comment.text
  |> wrap.truncate(500)
  |> wrap.wrap(width)
  |> list.map(fn(text) { Line("  " <> text, Plain) })
}

fn parent_context(parent: Comment, depth: Int, inner: Int) -> List(Line) {
  let header =
    "↩ Replying to "
    <> author_label(parent)
    <> " (depth "
    <> int.to_string(depth)
    <> ")"

  let text =
    parent.text
    |> wrap.truncate(200)
    |> wrap.wrap(int.max(inner - 2, 8))
    |> list.take(3)
    |> list.map(fn(line) { Line("  " <> line, Plain) })

  list.append(
    [Line(wrap.fit(header, inner), Meta)],
    list.append(text, [
      Line("", Plain),
    ]),
  )
}

// Search

fn editing(draft: String, cursor: Int, inner: Int, rows: Int) -> List(Line) {
  let cursor = int.clamp(cursor, 0, string.length(draft))
  let before = string.slice(draft, 0, cursor)
  let after = string.slice(draft, cursor, string.length(draft) - cursor)
  let prompt = "Search: " <> before <> "█" <> after
  let hint = "Enter to search · Esc to cancel · Backspace to delete"
  list.append(
    [
      Line(wrap.fit(prompt, inner), Title),
      Line("", Plain),
      Line(wrap.fit(hint, inner), Hint),
    ],
    blanks(rows - 3),
  )
}

fn search_outcome(
  model: m.Model,
  outcome: m.SearchOutcome,
  inner: Int,
  rows: Int,
) -> List(Line) {
  case outcome {
    m.SearchInFlight(query:, ..) ->
      message("Searching for \"" <> query.to_string(query) <> "…\"", rows)
    m.SearchFound(query:, stories:) ->
      case listing.is_empty(stories) {
        True ->
          message(
            "No results found for \"" <> query.to_string(query) <> "\"",
            rows,
          )
        False -> story_panel(stories, model.now, inner, rows)
      }
    m.SearchFailed(_, problem) -> failure(problem, inner, rows)
  }
}

// Lists

fn story_panel(
  items: listing.Listing(Story),
  now: Timestamp,
  inner: Int,
  rows: Int,
) -> List(Line) {
  let selected = listing.index(items) |> option_unwrap(0)
  let entries =
    listing.indexed(items)
    |> list.map(fn(entry) {
      #(story_text(entry.1, entry.0, now, inner), entry.0 == selected)
    })

  let heights = list.map(entries, fn(_entry) { 1 })
  let #(start, end) = viewport.window(heights, selected, rows)
  let visible = entries |> list.drop(start) |> list.take(end - start)

  visible
  |> list.map(fn(entry) {
    case entry.1 {
      True -> Line(entry.0, Selected)
      False -> Line(entry.0, Plain)
    }
  })
  |> pad_lines(rows)
}

fn story_text(story: Story, index: Int, now: Timestamp, inner: Int) -> String {
  let rank = wrap.pad_left(int.to_string(index + 1) <> ".", 4) <> " "
  let score = wrap.pad_left(int.to_string(story.score), 4)
  let comments = wrap.pad_left(int.to_string(story.comment_count) <> "c", 4)
  let age =
    wrap.pad_left(relative_time.relative(now:, then: story.posted_at), 4)
  let fixed = 4 + 1 + 4 + 2 + 2 + 4 + 2 + 4
  let title_width = int.max(inner - fixed, 8)

  rank
  <> score
  <> "  "
  <> wrap.fit(story.title, title_width)
  <> "  "
  <> comments
  <> "  "
  <> age
}

// Small helpers

fn message(text: String, rows: Int) -> List(Line) {
  list.append([Line(text, Plain)], blanks(rows - 1))
}

fn failure(problem: error.AppError, inner: Int, rows: Int) -> List(Line) {
  let lines =
    error.describe_with_retry(problem)
    |> wrap.wrap(int.max(inner, 20))
    |> list.map(fn(text) { Line(text, Error) })
  pad_lines(lines, rows)
}

fn blanks(count: Int) -> List(Line) {
  list.repeat(Line("", Plain), int.max(count, 0))
}

fn pad_lines(lines: List(Line), rows: Int) -> List(Line) {
  let missing = rows - list.length(lines)
  list.append(lines, blanks(missing))
}

fn comment_word(count: Int) -> String {
  case count == 1 {
    True -> " comment"
    False -> " comments"
  }
}

fn story_author_label(story: Story) -> String {
  case story.author {
    Some(author) if author != "" -> author
    None -> "[deleted]"
    Some(_) -> "[deleted]"
  }
}

fn option_unwrap(value: Option(a), default: a) -> a {
  case value {
    Some(inner) -> inner
    None -> default
  }
}
