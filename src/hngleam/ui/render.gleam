//// The only module that knows about shore's rendering primitives: it maps a
//// `Frame` of styled lines onto a column of text nodes.

import gleam/list
import gleam/option.{type Option, None, Some}
import hngleam/app/msg.{type Msg}
import hngleam/ui/layout.{
  type Frame, type Line, type LineStyle, Border, Error, Hint, Meta, Notice,
  Plain, Selected, TabActive, TabInactive, Title,
}
import shore
import shore/style
import shore/ui

/// Turn a frame into the node tree shore draws.
pub fn to_node(frame: Frame) -> shore.Node(Msg) {
  frame.lines
  |> list.map(to_node_line)
  |> ui.col
}

fn to_node_line(line: Line) -> shore.Node(Msg) {
  let #(fg, bg) = colors(line.style)
  ui.text_styled(line.text, fg, bg)
}

fn colors(style: LineStyle) -> #(Option(style.Color), Option(style.Color)) {
  case style {
    Border -> #(Some(style.Yellow), None)
    Title -> #(Some(style.Yellow), None)
    TabActive -> #(Some(style.Yellow), None)
    TabInactive -> #(Some(style.White), None)
    // ANSI blue is a light colour in most current themes, so white text
    // disappears into the highlight. Black stays readable on it.
    Selected -> #(Some(style.Black), Some(style.Blue))
    Meta -> #(Some(style.Cyan), None)
    Error -> #(Some(style.Red), None)
    Notice -> #(Some(style.Magenta), None)
    Hint -> #(Some(style.Cyan), None)
    Plain -> #(None, None)
  }
}
