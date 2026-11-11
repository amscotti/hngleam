//// A bounded parallel map with a deadline.
////
//// The UI must never block on I/O, so commands run in shore's unlinked
//// processes. Fetching 75 stories one after another would take seconds, so
//// this module spreads the work across at most `concurrency` processes and
//// gives the whole batch a single deadline. Results keep the input order;
//// anything that has not arrived by the deadline is reported as `None` so the
//// caller can decide what a missing value means.
////
//// The gate that hands out slots is stopped when the batch finishes, and a
//// worker that crashes gives its slot back. Waiters are served oldest first,
//// so the top of a feed is not stuck behind later items.

import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// Apply `with` to every item, running at most `concurrency` at a time, and
/// waiting no longer than `timeout_ms` overall. The result has one entry per
/// input, in the same order; `None` means the item did not finish in time.
pub fn map(
  items: List(a),
  concurrency: Int,
  timeout_ms: Int,
  apply apply: fn(a) -> b,
) -> List(Option(b)) {
  let count = list.length(items)
  case count {
    0 -> []
    _ -> {
      let gate = spawn_gate(int.max(1, concurrency))
      let results = process.new_subject()
      let deadline = monotonic_ms() + int.max(1, timeout_ms)

      items
      |> list.index_map(fn(item, index) {
        process.spawn_unlinked(fn() {
          case acquire(gate) {
            False -> Nil
            True -> {
              let value = apply(item)
              release(gate)
              process.send(results, #(index, value))
            }
          }
        })
      })

      let collected = collect(results, count, deadline, dict.new())
      process.send(gate, Stop)
      collected
    }
  }
}

fn collect(
  results: process.Subject(#(Int, b)),
  count: Int,
  deadline: Int,
  gathered: dict.Dict(Int, b),
) -> List(Option(b)) {
  case dict.size(gathered) >= count {
    True -> in_order(0, count, gathered)
    False -> {
      let remaining = deadline - monotonic_ms()
      case remaining <= 0 {
        True -> in_order(0, count, gathered)
        False ->
          case process.receive(results, remaining) {
            Ok(#(index, value)) ->
              collect(
                results,
                count,
                deadline,
                dict.insert(gathered, index, value),
              )
            Error(_) -> in_order(0, count, gathered)
          }
      }
    }
  }
}

fn in_order(
  index: Int,
  count: Int,
  gathered: dict.Dict(Int, b),
) -> List(Option(b)) {
  case index >= count {
    True -> []
    False -> {
      let value = case dict.get(gathered, index) {
        Ok(found) -> Some(found)
        Error(_) -> None
      }
      [value, ..in_order(index + 1, count, gathered)]
    }
  }
}

// A counting semaphore. Acquiring a slot when none is free parks the caller;
// releasing a slot hands it to the oldest waiter.

type GateMessage {
  Acquire(reply: process.Subject(Bool))
  Release(pid: process.Pid)
  Stop
}

type Waiter {
  Waiter(pid: process.Pid, reply: process.Subject(Bool))
}

type Incoming {
  Request(GateMessage)
  Exited(process.Pid)
}

fn spawn_gate(limit: Int) -> process.Subject(GateMessage) {
  let ready = process.new_subject()
  let fallback = process.new_subject()
  process.spawn_unlinked(fn() {
    let inbox = process.new_subject()
    process.send(ready, inbox)
    gate_loop(limit, new_queue(), [], inbox)
  })
  case process.receive(ready, 1000) {
    Ok(inbox) -> inbox
    Error(_) -> fallback
  }
}

fn gate_loop(
  available: Int,
  waiting: Queue(Waiter),
  held: List(process.Pid),
  inbox: process.Subject(GateMessage),
) -> Nil {
  let selector =
    process.new_selector()
    |> process.select_map(inbox, Request)
    |> process.select_monitors(fn(down) {
      case down {
        process.ProcessDown(pid:, ..) -> Exited(pid)
        process.PortDown(..) -> Exited(process.self())
      }
    })

  case process.selector_receive_forever(selector) {
    Request(Acquire(reply)) ->
      on_acquire(available, waiting, held, inbox, reply)
    Request(Release(pid)) -> on_down(available, waiting, held, inbox, pid)
    Request(Stop) -> {
      each_waiter(waiting, fn(waiter) { process.send(waiter.reply, False) })
      Nil
    }
    Exited(pid) -> on_down(available, waiting, held, inbox, pid)
  }
}

fn on_acquire(
  available: Int,
  waiting: Queue(Waiter),
  held: List(process.Pid),
  inbox: process.Subject(GateMessage),
  reply: process.Subject(Bool),
) -> Nil {
  case process.subject_owner(reply) {
    Error(_) -> {
      // Nobody to monitor. Hand out a slot rather than park the caller forever.
      process.send(reply, True)
      gate_loop(available, waiting, held, inbox)
    }
    Ok(pid) -> {
      let _monitor = process.monitor(pid)
      case available > 0 {
        True -> {
          process.send(reply, True)
          gate_loop(available - 1, waiting, [pid, ..held], inbox)
        }
        False ->
          gate_loop(available, push(waiting, Waiter(pid:, reply:)), held, inbox)
      }
    }
  }
}

/// A holder finished or crashed. Freeing a pid that is not holding a slot is
/// a no-op, so a normal exit followed by its down message cannot double-free.
fn on_down(
  available: Int,
  waiting: Queue(Waiter),
  held: List(process.Pid),
  inbox: process.Subject(GateMessage),
  pid: process.Pid,
) -> Nil {
  let waiting = reject(waiting, fn(waiter) { waiter.pid == pid })
  case list.contains(held, pid) {
    False -> gate_loop(available, waiting, held, inbox)
    True -> {
      let held = list.filter(held, fn(holder) { holder != pid })
      case pop(waiting) {
        Ok(#(waiter, rest)) -> {
          process.send(waiter.reply, True)
          gate_loop(available, rest, [waiter.pid, ..held], inbox)
        }
        Error(_) -> gate_loop(available + 1, waiting, held, inbox)
      }
    }
  }
}

fn acquire(gate: process.Subject(GateMessage)) -> Bool {
  let reply = process.new_subject()
  process.send(gate, Acquire(reply:))
  case process.subject_owner(gate) {
    Error(_) -> False
    Ok(pid) -> {
      let monitor = process.monitor(pid)
      wait_for_slot(reply, monitor)
    }
  }
}

type Slot {
  Granted(Bool)
  GateExited
}

fn wait_for_slot(
  reply: process.Subject(Bool),
  monitor: process.Monitor,
) -> Bool {
  let selector =
    process.new_selector()
    |> process.select_map(reply, Granted)
    |> process.select_specific_monitor(monitor, fn(_down) { GateExited })
  case process.selector_receive_forever(selector) {
    Granted(allowed) -> allowed
    GateExited -> False
  }
}

fn release(gate: process.Subject(GateMessage)) -> Nil {
  process.send(gate, Release(process.self()))
}

// A two-list queue. Items leave in the order they arrived.

type Queue(a) {
  Queue(front: List(a), back: List(a))
}

fn new_queue() -> Queue(a) {
  Queue(front: [], back: [])
}

fn push(queue: Queue(a), item: a) -> Queue(a) {
  Queue(front: queue.front, back: [item, ..queue.back])
}

fn pop(queue: Queue(a)) -> Result(#(a, Queue(a)), Nil) {
  case queue.front {
    [first, ..rest] -> Ok(#(first, Queue(front: rest, back: queue.back)))
    [] ->
      case list.reverse(queue.back) {
        [] -> Error(Nil)
        [first, ..rest] -> Ok(#(first, Queue(front: rest, back: [])))
      }
  }
}

fn reject(queue: Queue(a), drop: fn(a) -> Bool) -> Queue(a) {
  Queue(
    front: list.filter(queue.front, fn(item) { !drop(item) }),
    back: list.filter(queue.back, fn(item) { !drop(item) }),
  )
}

fn each_waiter(queue: Queue(Waiter), run: fn(Waiter) -> Nil) -> Nil {
  list.each(queue.front, run)
  list.each(list.reverse(queue.back), run)
}

@external(erlang, "hngleam_ffi", "monotonic_ms")
fn monotonic_ms() -> Int
