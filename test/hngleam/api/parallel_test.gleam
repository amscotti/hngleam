import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import hngleam/api/parallel

pub fn results_keep_the_input_order_test() {
  parallel.map([1, 2, 3, 4], 2, 5000, fn(item) { item * 10 })
  |> should.equal([Some(10), Some(20), Some(30), Some(40)])
}

pub fn an_empty_input_is_an_empty_output_test() {
  parallel.map([], 4, 1000, fn(item) { item })
  |> should.equal([])
}

pub fn slow_items_time_out_test() {
  let results =
    parallel.map([1, 2], 2, 300, fn(item) {
      case item {
        2 -> {
          process.sleep(1000)
          item
        }
        _ -> item
      }
    })
  results |> should.equal([Some(1), None])
}

pub fn finished_batches_do_not_leave_processes_test() {
  let before = process_count()
  list.each(numbers(1, 20), fn(_) {
    parallel.map([1], 1, 2000, fn(item) { item })
  })
  process.sleep(100)
  let growth = process_count() - before
  { growth < 5 } |> should.be_true()
}

pub fn waiters_run_in_arrival_order_test() {
  let started = process.new_subject()
  let _ =
    parallel.map([1, 2, 3, 4], 1, 5000, fn(item) {
      process.send(started, item)
      case item {
        1 -> process.sleep(120)
        _ -> Nil
      }
      item
    })
  receive_all(started, 4, []) |> should.equal([1, 2, 3, 4])
}

/// The first worker panics on purpose. It is unlinked, so the test process
/// survives; Erlang still prints a crash report for that worker.
pub fn a_crashed_worker_releases_its_slot_test() {
  parallel.map([1, 2], 1, 2000, fn(item) {
    case item {
      1 -> panic as "worker crashed"
      _ -> item
    }
  })
  |> should.equal([None, Some(2)])
}

pub fn concurrency_never_exceeds_the_limit_test() {
  let counter = spawn_counter()
  let _ =
    parallel.map(numbers(1, 9), 3, 10_000, fn(_item) {
      process.send(counter, Enter)
      process.sleep(40)
      process.send(counter, Leave)
    })

  let #(_current, highest) = read_counter(counter)
  { highest <= 3 } |> should.be_true()
  { highest > 1 } |> should.be_true()
}

type CounterMessage {
  Enter
  Leave
  Read(reply: process.Subject(#(Int, Int)))
}

fn spawn_counter() -> process.Subject(CounterMessage) {
  let ready = process.new_subject()
  let fallback = process.new_subject()
  let _ =
    process.spawn(fn() {
      let inbox = process.new_subject()
      process.send(ready, inbox)
      counter_loop(0, 0, inbox)
    })
  case process.receive(ready, 1000) {
    Ok(inbox) -> inbox
    Error(_) -> fallback
  }
}

fn counter_loop(
  current: Int,
  highest: Int,
  inbox: process.Subject(CounterMessage),
) -> Nil {
  case process.receive_forever(inbox) {
    Enter -> counter_loop(current + 1, int.max(highest, current + 1), inbox)
    Leave -> counter_loop(current - 1, highest, inbox)
    Read(reply) -> {
      process.send(reply, #(current, highest))
      counter_loop(current, highest, inbox)
    }
  }
}

fn read_counter(counter: process.Subject(CounterMessage)) -> #(Int, Int) {
  let reply = process.new_subject()
  process.send(counter, Read(reply))
  process.receive_forever(reply)
}

fn receive_all(
  subject: process.Subject(Int),
  count: Int,
  acc: List(Int),
) -> List(Int) {
  case count {
    0 -> list.reverse(acc)
    _ ->
      case process.receive(subject, 2000) {
        Ok(item) -> receive_all(subject, count - 1, [item, ..acc])
        Error(_) -> list.reverse(acc)
      }
  }
}

@external(erlang, "hngleam_ffi", "process_count")
fn process_count() -> Int

fn numbers(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..numbers(from + 1, to)]
  }
}
