//// Which key does what, per screen. Pure data, so the view can emit exactly
//// the bindings for the screen being drawn and tests can assert on them.

import gleam/int
import gleam/list
import gleam/string
import hngleam/app/model.{
  type Model, Browsing, Editing, Reading, Searching, Showing,
}
import hngleam/app/msg.{
  type Action, Back, CancelSearch, CursorEnd, CursorHome, CursorLeft,
  CursorRight, DeleteForward, Erase, Next, NextFeed, OpenComment, OpenDetail,
  OpenStory, Previous, Quit, Reload, SelectFeed, StartSearch, SubmitSearch,
  Typed,
}
import hngleam/domain/feed
import shore/key.{type Key}

/// The bindings for the current screen.
pub fn for_model(model: Model) -> List(#(Key, Action)) {
  case model.screen {
    Browsing ->
      list.append(feed_keys(), [
        #(key.Char("j"), Next),
        #(key.Down, Next),
        #(key.Char("k"), Previous),
        #(key.Up, Previous),
        #(key.Char("l"), OpenDetail),
        #(key.Right, OpenDetail),
        #(key.Enter, OpenDetail),
        #(key.Char("o"), OpenStory),
        #(key.Char("r"), Reload),
        #(key.Char("/"), StartSearch),
        #(key.Tab, NextFeed),
        #(key.Char("q"), Quit),
        #(key.Esc, Quit),
        #(key.Ctrl("C"), Quit),
      ])
    Reading(..) ->
      list.append(feed_keys(), [
        #(key.Char("j"), Next),
        #(key.Down, Next),
        #(key.Char("k"), Previous),
        #(key.Up, Previous),
        #(key.Char("l"), OpenDetail),
        #(key.Right, OpenDetail),
        #(key.Enter, OpenDetail),
        #(key.Char("h"), Back),
        #(key.Left, Back),
        #(key.Char("o"), OpenStory),
        #(key.Char("c"), OpenComment),
        #(key.Char("r"), Reload),
        #(key.Char("q"), Quit),
        #(key.Esc, Quit),
        #(key.Ctrl("C"), Quit),
      ])
    Searching(Editing(..)) -> editing_keys()
    Searching(Showing(..)) -> [
      #(key.Char("j"), Next),
      #(key.Down, Next),
      #(key.Char("k"), Previous),
      #(key.Up, Previous),
      #(key.Char("l"), OpenDetail),
      #(key.Right, OpenDetail),
      #(key.Enter, OpenDetail),
      #(key.Char("o"), OpenStory),
      #(key.Char("r"), Reload),
      #(key.Char("/"), StartSearch),
      #(key.Char("q"), Quit),
      #(key.Esc, CancelSearch),
      #(key.Ctrl("C"), Quit),
    ]
  }
}

/// The numbered feed shortcuts.
pub fn feed_keys() -> List(#(Key, Action)) {
  feed.all()
  |> list.map(fn(feed) {
    #(key.Char(int.to_string(feed.index(feed))), SelectFeed(feed))
  })
}

fn editing_keys() -> List(#(Key, Action)) {
  list.append(printable_keys(), [
    #(key.Backspace, Erase),
    #(key.Delete, DeleteForward),
    #(key.Left, CursorLeft),
    #(key.Right, CursorRight),
    #(key.Home, CursorHome),
    #(key.End, CursorEnd),
    #(key.Enter, SubmitSearch),
    #(key.Esc, CancelSearch),
    #(key.Ctrl("C"), Quit),
  ])
}

/// Printable characters type themselves. Latin-1 covers accented letters the
/// terminal delivers as one key. A paste arrives as one multi-character key
/// and does not match any of these; see the README. Characters outside this
/// set, including CJK, are not delivered as bindable keys by shore.
fn printable_keys() -> List(#(Key, Action)) {
  list.append(keys_of(printable), keys_of(latin1()))
}

fn keys_of(text: String) -> List(#(Key, Action)) {
  text
  |> string.to_graphemes()
  |> list.map(fn(character) { #(key.Char(character), Typed(character)) })
}

fn latin1() -> String {
  codepoints(0x00a1, 0x00ff, "")
}

fn codepoints(from: Int, to: Int, acc: String) -> String {
  case from > to {
    True -> acc
    False ->
      case string.utf_codepoint(from) {
        Ok(point) ->
          codepoints(from + 1, to, acc <> string.from_utf_codepoints([point]))
        Error(_) -> codepoints(from + 1, to, acc)
      }
  }
}

const printable: String =
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
