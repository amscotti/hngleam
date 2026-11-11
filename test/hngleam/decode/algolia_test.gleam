import gleam/list
import gleam/string
import gleeunit/should
import hngleam/decode/algolia
import simplifile

pub fn search_results_decode_test() {
  case simplifile.read("test/fixtures/search_gleam.json") {
    Error(_) -> panic as "missing search fixture"
    Ok(json) ->
      case algolia.decode_search(json) {
        Error(_) -> panic as "expected search results"
        Ok(stories) -> {
          { stories != [] } |> should.be_true()
          stories
          |> list.all(fn(story) { string.contains(story.title, "Gleam") })
          |> should.be_true()
        }
      }
  }
}

pub fn null_hit_fields_and_entities_decode_test() {
  let json =
    "{\"hits\":[{\"objectID\":\"9\",\"title\":\"A &amp; B\",\"url\":null,\"author\":null,\"points\":null,\"created_at_i\":null,\"num_comments\":null},{\"objectID\":\"10\",\"title\":null}]}"
  case algolia.decode_search(json) {
    Error(_) -> panic as "expected the hit to decode"
    Ok(stories) -> {
      list.length(stories) |> should.equal(1)
      case stories {
        [story] -> story.title |> should.equal("A & B")
        _ -> panic as "expected one story"
      }
    }
  }
}

pub fn malformed_search_is_an_error_test() {
  case algolia.decode_search("{\"hits\": 3}") {
    Ok(_) -> panic as "expected a decode error"
    Error(errors) -> { errors != [] } |> should.be_true()
  }
}
