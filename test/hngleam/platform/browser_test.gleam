import gleeunit/should
import hngleam/app/error.{BrowserUnavailable}
import hngleam/platform/browser

pub fn only_http_urls_are_accepted_test() {
  browser.web_url("https://news.ycombinator.com/item?id=1")
  |> should.be_ok()
  browser.web_url("http://example.com") |> should.be_ok()
  browser.web_url("javascript:alert(1)")
  |> should.equal(
    Error(BrowserUnavailable(command: "only http and https links can be opened")),
  )
  browser.web_url("file:///etc/passwd") |> should.be_error()
  browser.web_url("https://example.com/a\nb") |> should.be_error()
  browser.web_url("https://example.com/a b") |> should.be_error()
}

pub fn darwin_prefers_open_test() {
  browser.choose_opener(
    on_darwin: True,
    xdg: Ok("/usr/bin/xdg-open"),
    open: Ok("/usr/bin/open"),
  )
  |> should.equal(Ok("/usr/bin/open"))

  browser.choose_opener(
    on_darwin: False,
    xdg: Ok("/usr/bin/xdg-open"),
    open: Ok("/usr/bin/open"),
  )
  |> should.equal(Ok("/usr/bin/xdg-open"))

  browser.choose_opener(on_darwin: True, xdg: Error(Nil), open: Error(Nil))
  |> should.be_error()
}
