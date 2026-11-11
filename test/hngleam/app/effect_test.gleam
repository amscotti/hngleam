import gleam/time/timestamp
import gleeunit/should
import hngleam/app/effect

pub fn the_displayed_minute_ignores_seconds_test() {
  effect.minute_bucket(timestamp.from_unix_seconds(59)) |> should.equal(0)
  effect.minute_bucket(timestamp.from_unix_seconds(60)) |> should.equal(1)
  effect.minute_bucket(timestamp.from_unix_seconds(119)) |> should.equal(1)
}
