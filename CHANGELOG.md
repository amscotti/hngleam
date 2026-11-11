# Changelog

## Unreleased

- Gleam 1.19.2 or newer is required.
- The selected row draws dark text on the highlight so the title stays readable.
- `1`–`5` leave a story or any level of its comments and open that feed.
- GitHub Actions checks the format, the build, and the tests. A `v*` tag
  publishes the escript.
- Each HTTP request closes its socket and reads until one deadline, the
  Content-Length, or the end of a chunked body. Chunk extensions are ignored.
- Transport failures are reported in a short sentence.
- A feed response is applied when that feed is still loading, including when a
  search has started in the meantime.
- Search can be reloaded. The query has a cursor. Esc while refining restores
  the previous results. Ctrl-C quits.
- Comment HTML keeps whitespace inside `<pre>`, decodes numeric entities, and
  keeps a `<` that does not start a tag. Titles are entity-decoded. Control
  sequences are removed from untrusted text. Wide characters count as two
  columns.
- The browser opens only `http` and `https` links. Terminal settings are
  restored on exit and on SIGTERM or SIGHUP.

## 1.0.0

First release.

- Browse the Top, New, Best, Ask HN and Show HN feeds, 75 stories each.
- Move through stories with `j`/`k` or the arrow keys; the list scrolls to keep
  the selection visible.
- Open a story's discussion, read comments, drill into replies and back out.
- Search Hacker News through Algolia.
- Open stories or comments in the system browser.
- Reload the current feed or discussion.
- Typed errors for network, timeout, HTTP status, decoding and browser
  failures, shown in the content area or the status bar.
- Stale responses are discarded by generation token, so fast feed switching
  never shows the wrong stories.
- Ships as a single-file escript.
