import gleam/time/timestamp
import gleeunit/should
import hngleam/text/relative_time

fn at(seconds: Int) -> timestamp.Timestamp {
  timestamp.from_unix_seconds(seconds)
}

pub fn seconds_ago_is_now_test() {
  relative_time.relative(now: at(1000), then: at(970)) |> should.equal("now")
}

pub fn minutes_test() {
  relative_time.relative(now: at(1000), then: at(700)) |> should.equal("5m")
}

pub fn hours_test() {
  relative_time.relative(now: at(20_000), then: at(20_000 - 10_800))
  |> should.equal("3h")
}

pub fn days_test() {
  relative_time.relative(now: at(200_000), then: at(200_000 - 172_800))
  |> should.equal("2d")
}

pub fn long_ages_switch_to_years_test() {
  // Three years, so the column stays narrow.
  relative_time.relative(now: at(100_000_000), then: at(1))
  |> should.equal("3y")
}

pub fn future_timestamps_are_now_test() {
  relative_time.relative(now: at(1000), then: at(2000)) |> should.equal("now")
}

pub fn the_unix_epoch_is_a_missing_time_test() {
  relative_time.relative(now: at(1_700_000_000), then: at(0))
  |> should.equal("-")
}
