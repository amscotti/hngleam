import gleeunit/should
import hngleam/domain/feed

pub fn five_feeds_in_tab_order_test() {
  feed.all()
  |> should.equal([feed.Top, feed.New, feed.Best, feed.Ask, feed.Show])
}

pub fn next_cycles_through_every_feed_test() {
  feed.Top |> feed.next() |> should.equal(feed.New)
  feed.New |> feed.next() |> should.equal(feed.Best)
  feed.Best |> feed.next() |> should.equal(feed.Ask)
  feed.Ask |> feed.next() |> should.equal(feed.Show)
  feed.Show |> feed.next() |> should.equal(feed.Top)
}

pub fn digits_map_to_feeds_test() {
  feed.from_digit("1") |> should.equal(Ok(feed.Top))
  feed.from_digit("2") |> should.equal(Ok(feed.New))
  feed.from_digit("3") |> should.equal(Ok(feed.Best))
  feed.from_digit("4") |> should.equal(Ok(feed.Ask))
  feed.from_digit("5") |> should.equal(Ok(feed.Show))
}

pub fn other_digits_are_rejected_test() {
  feed.from_digit("0") |> should.be_error()
  feed.from_digit("6") |> should.be_error()
  feed.from_digit("a") |> should.be_error()
}

pub fn labels_and_endpoints_test() {
  feed.tab_label(feed.Ask) |> should.equal("4:Ask HN")
  feed.endpoint(feed.Show) |> should.equal("showstories")
  feed.index(feed.Best) |> should.equal(3)
  feed.label(feed.Top) |> should.equal("Top")
}

pub fn tabs_are_a_stable_width_test() {
  // "4:Ask HN" and "5:Show HN" are the widest labels.
  feed.tab_width() |> should.equal(9)
}
