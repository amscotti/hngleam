import gleam/list
import gleeunit/should
import hngleam/text/html

pub fn paragraphs_become_blank_lines_test() {
  html.to_text("<p>first</p><p>second</p>")
  |> should.equal("first\n\nsecond")
}

pub fn line_breaks_become_newlines_test() {
  html.to_text("first<br>second") |> should.equal("first\nsecond")
  html.to_text("first<br/>second") |> should.equal("first\nsecond")
}

pub fn tags_are_stripped_test() {
  html.to_text("a <i>little</i> <a href=\"https://x.test\">link</a>")
  |> should.equal("a little link")
}

pub fn entities_are_decoded_test() {
  // Table driven: entity in, text out.
  [
    #("&gt;", ">"),
    #("&lt;", "<"),
    #("&amp;", "&"),
    #("&quot;", "\""),
    #("&#x27;", "'"),
    #("&#x2F;", "/"),
  ]
  |> list.each(fn(pair) { html.to_text(pair.0) |> should.equal(pair.1) })
}

pub fn non_breaking_spaces_become_spaces_test() {
  html.to_text("a&nbsp;b") |> should.equal("a b")
}

pub fn unknown_entities_are_left_alone_test() {
  html.to_text("a &bogus; b") |> should.equal("a &bogus; b")
}

pub fn list_items_get_bullets_test() {
  html.to_text("<ul><li>one</li><li>two</li></ul>")
  |> should.equal("• one\n• two")
}

pub fn whitespace_is_normalised_test() {
  html.to_text("<p>one    two\n\n\n\nthree</p>")
  |> should.equal("one two\n\nthree")
}

pub fn code_blocks_are_kept_test() {
  html.to_text("<pre><code>let x = 1\nlet y = 2</code></pre>")
  |> should.equal("let x = 1\nlet y = 2")
}

pub fn a_less_than_sign_that_is_not_a_tag_is_kept_test() {
  html.to_text("a < b and c > d") |> should.equal("a < b and c > d")
  html.to_text("before < unclosed") |> should.equal("before < unclosed")
}

pub fn tag_names_are_matched_exactly_test() {
  html.to_text("<picture></picture><p>yes</p>") |> should.equal("yes")
  html.to_text("<link rel=\"x\">item") |> should.equal("item")
  html.to_text("<li>item</li>") |> should.equal("• item")
}

pub fn numeric_entities_are_decoded_test() {
  html.to_text("&#39; and &#x3d;") |> should.equal("' and =")
  html.decode_entities("A &amp; B") |> should.equal("A & B")
}

pub fn numeric_character_references_outside_the_named_table_are_decoded_test() {
  html.to_text("&#65;") |> should.equal("A")
  html.to_text("&#x42;") |> should.equal("B")
  html.to_text("&#X43;") |> should.equal("C")
  html.to_text("say &#65; now") |> should.equal("say A now")
}

pub fn malformed_numeric_entities_are_left_alone_test() {
  html.to_text("&#;") |> should.equal("&#;")
  html.to_text("&#x;") |> should.equal("&#x;")
  html.to_text("&#12g;") |> should.equal("&#12g;")
  html.to_text("&#65") |> should.equal("&#65")
  html.to_text("&#1114112;") |> should.equal("&#1114112;")
}

pub fn preformatted_whitespace_is_preserved_test() {
  html.to_text("<pre>  indented\n    more</pre>")
  |> should.equal("  indented\n    more")
}

pub fn terminal_control_sequences_are_stripped_test() {
  html.to_text("hi\u{001b}[31mred") |> should.equal("hired")
  html.to_text("\u{001b}]0;evil\u{0007}ok") |> should.equal("ok")
  html.to_text("a\u{0001}b") |> should.equal("ab")
}
