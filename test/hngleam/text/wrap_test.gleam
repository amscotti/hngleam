import gleam/list
import gleam/string
import gleeunit/should
import hngleam/text/width
import hngleam/text/wrap

pub fn wraps_at_word_boundaries_test() {
  wrap.wrap("the quick brown fox jumps", 10)
  |> should.equal(["the quick", "brown fox", "jumps"])
}

pub fn long_words_are_split_test() {
  let lines = wrap.wrap("abcdefghijklmnopqrstuvwxyz", 10)
  lines |> should.equal(["abcdefghij", "klmnopqrst", "uvwxyz"])
}

pub fn never_exceeds_the_width_test() {
  // A long URL with no spaces is split into lines of at most 20 columns.
  let url = "https://example.com/" <> string.repeat("a", 300)
  let lines = wrap.wrap(url, 20)
  lines
  |> list.all(fn(line) { string.length(line) <= 20 })
  |> should.be_true()
  { list.length(lines) > 1 } |> should.be_true()
}

pub fn newlines_start_new_paragraphs_test() {
  wrap.wrap("one\ntwo", 20) |> should.equal(["one", "two"])
}

pub fn empty_paragraphs_are_kept_test() {
  wrap.wrap("one\n\ntwo", 20) |> should.equal(["one", "", "two"])
}

pub fn truncate_marks_the_cut_test() {
  wrap.truncate("abcdefgh", 5) |> should.equal("abcd…")
  wrap.truncate("abc", 5) |> should.equal("abc")
  wrap.truncate("abcdefgh", 1) |> should.equal("…")
}

pub fn fit_pads_to_an_exact_width_test() {
  wrap.fit("ab", 5) |> should.equal("ab   ")
  wrap.fit("abcdef", 4) |> should.equal("abc…")
  wrap.fit("abc", 4) |> string.length() |> should.equal(4)
}

pub fn pad_left_pads_numbers_test() {
  wrap.pad_left("7", 4) |> should.equal("   7")
  wrap.pad_left("1234", 4) |> should.equal("1234")
}

pub fn wide_characters_count_as_two_columns_test() {
  width.columns("你好") |> should.equal(4)
  width.columns("a\u{200B}b") |> should.equal(2)
  wrap.truncate("你好", 3) |> should.equal("你…")
  wrap.wrap("你好世界", 4) |> should.equal(["你好", "世界"])
}
