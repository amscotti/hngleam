//// The entry point: check there is a terminal, start shore, wire the effect
//// interpreter to the live client, and make sure the terminal is restored on
//// every exit path.

import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/time/timestamp
import hngleam/api/client
import hngleam/app/effect
import hngleam/app/keymap
import hngleam/app/model as m
import hngleam/app/msg.{type Msg, Pressed}
import hngleam/app/update
import hngleam/domain/terminal_size
import hngleam/platform/terminal
import hngleam/ui/layout
import hngleam/ui/render
import shellout
import shore
import shore/key
import shore/ui

/// Run the reader.
pub fn main() -> Nil {
  case terminal.size() {
    Error(_) -> no_terminal()
    Ok(size) -> run(size)
  }
}

fn no_terminal() -> Nil {
  io.println_error(
    "hngleam needs a terminal: run it in a terminal window with TERM set.",
  )
  shellout.exit(1)
}

fn run(size: terminal_size.TerminalSize) -> Nil {
  terminal.prepare()
  let api = client.live()
  let quit = process.new_subject()
  let exit = process.new_subject()

  let spec =
    shore.spec(
      init: fn() {
        let #(model, effects) = update.init(size, timestamp.system_time())
        #(model, commands(effects, api, quit))
      },
      update: fn(model, msg) {
        let #(model, effects) = update.update(model, msg)
        #(model, commands(effects, api, quit))
      },
      view: view,
      exit: exit,
      keybinds: shore.keybinds(
        exit: key.Ctrl("X"),
        submit: key.Enter,
        // Tab and Esc belong to the application, so the focus keys move out of
        // the way to unused function keys.
        focus_clear: key.F(10),
        focus_next: key.F(11),
        focus_prev: key.F(12),
      ),
      redraw: shore.on_update(),
    )

  case shore.start(spec) {
    Error(_) -> {
      io.println_error("hngleam: the UI could not start.")
      shellout.exit(1)
    }
    Ok(actor) -> supervise(actor, quit, exit)
  }
}

fn commands(
  effects: List(effect.Effect),
  api: client.Client,
  quit: process.Subject(Nil),
) -> List(fn() -> Msg) {
  list.map(effects, fn(effect) { effect.to_command(effect, api, quit) })
}

fn view(model: m.Model) -> shore.Node(Msg) {
  let bindings =
    keymap.for_model(model)
    |> list.map(fn(pair) { ui.keybind(pair.0, Pressed(pair.1)) })

  ui.col([render.to_node(layout.frame(model)), ..bindings])
}

/// Messages the supervisor waits for while the UI runs.
type Supervision {
  QuitRequested
  UIFinished
  UIGone(reason: process.ExitReason)
}

/// Owns the terminal lifetime. Quitting goes through shore so that it can
/// restore the terminal; if the UI process dies without doing so, the escape
/// codes are written here before exiting non-zero.
fn supervise(
  actor: process.Subject(shore.Event(Msg)),
  quit: process.Subject(Nil),
  exit: process.Subject(Nil),
) -> Nil {
  let base =
    process.new_selector()
    |> process.select_map(quit, fn(_) { QuitRequested })
    |> process.select_map(exit, fn(_) { UIFinished })

  let selector = case process.subject_owner(actor) {
    Error(_) -> base
    Ok(pid) -> {
      let _monitor = process.monitor(pid)
      process.select_monitors(base, fn(down) {
        case down {
          process.ProcessDown(reason:, ..) -> UIGone(reason:)
          process.PortDown(..) -> UIGone(reason: process.Normal)
        }
      })
    }
  }

  case process.selector_receive_forever(selector) {
    QuitRequested -> {
      process.send(actor, shore.exit())
      supervise(actor, quit, exit)
    }
    UIFinished -> Nil
    UIGone(reason: process.Normal) -> Nil
    UIGone(reason: _) -> {
      terminal.restore()
      io.println_error("\nhngleam: the UI stopped unexpectedly.")
      shellout.exit(1)
    }
  }
}
