# MarkdownKit

High-performance Markdown rendering for SwiftUI on iOS 26 and macOS 26, built for chat apps: long
conversations, token-by-token streaming, big tables, code, math and animated images. The goal is
smooth scrolling without hangs.

```swift
import MarkdownKit

MarkdownView(message.text)                          // static content
MarkdownView(partialReply, isStreaming: true)       // streaming: pass the growing text
```

## Features

- Full GitHub-flavored Markdown (via [swift-markdown](https://github.com/swiftlang/swift-markdown) / cmark-gfm):
  headings, emphasis, strikethrough, links, images, ordered, bullet and task lists, block quotes,
  fenced code, tables, thematic breaks, HTML as text.
- **Streaming**: incremental parsing (only the last block is re-parsed), reuse of already prepared blocks,
  display fixes for incomplete constructs (unclosed `**`, `` ` ``, `~~`, partial table rows), a streaming cursor.
- **Tables**: CoreText layout computed off the main thread, drawn by a few tiled `Canvas` views. Wide tables
  scroll horizontally. Links in cells are tappable, there's a context menu to copy as Markdown or TSV, and math
  can appear in cells. A 30×30 table lays out about 74× faster than a SwiftUI `Grid` of `Text`.
- **Inline attachments that flow with the text**: images, custom emoji (`:shortcode:` → text, image or
  SF Symbol), and inline math.
- **Math**: `$…$`, `$$…$$`, `\(…\)`, `\[…\]`, rendered with [SwiftMath](https://github.com/mgriebling/SwiftMath)
  (CoreText, no web view), inline (aligned to the baseline) or as blocks.
- **Animated images**: GIF, APNG, WebP and HEICS through ImageIO. They play inline, pause off screen, in the
  background, and with Reduce Motion.
- **Syntax highlighting**: an in-house single-pass highlighter covering 24 languages (Swift, Python, JS/TS,
  JSON, Kotlin, Java, C/C++/ObjC, C#, Go, Rust, Ruby, PHP, shell, SQL, HTML/XML, CSS, YAML, Markdown, diff,
  Dart, Scala) with built-in themes (`.xcode`, `.github`, `.monokai`, `.dracula`, `.solarized`).
- **Styling**: a theme covering headings, text, links, inline code, code blocks, quotes, lists, tables, rules,
  images and math. All sizes are **font-relative** (`.em`) and scale with Dynamic Type.

## Usage

### Chat transcripts

```swift
ScrollView {
    LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(messages) { message in
            // One lazy row per block, so long answers only build what's on screen.
            MarkdownBlocks(message.text, isStreaming: message.isStreaming)
                .padding(.horizontal, 16)
        }
    }
}
// Parse, prepare and typeset in the background before cells appear.
.markdownPrefetch(messages.map(\.text), width: containerWidth - 32)
```

`MarkdownBlocks` flattens a message into its blocks inside the enclosing `LazyVStack`. This is the
recommended way to show long conversations: in the scroll benchmark it causes about 4× fewer hitches than one
`MarkdownView` per message (see Benchmarks).

### Styling

```swift
MarkdownView(text)
    .markdownTheme(.compact)                              // or a full MarkdownTheme
    .markdownTheme { $0.link.color = .purple }            // tweak in place
    .markdownHeadingStyle(level: 1, .init(font: .init(scale: 2, weight: .heavy)))
    .markdownCodeTheme(.github)
    .markdownTableStyle(.init(maxColumnWidth: .em(20)))
    .markdownTextStyle(baseSize: 16, lineSpacing: .em(0.25))
    .markdownBlockSpacing(.em(0.6))
```

`MarkdownLength` is `.em(_)`, a multiple of the font size (which scales with Dynamic Type), or `.pt(_)`.

### Other modifiers

| Modifier | Purpose |
|---|---|
| `.markdownImageLoader(_:)` | Plug in your own image pipeline (`MarkdownImageLoader`). |
| `.markdownEmojiProvider { name in … }` | Resolve `:shortcode:` to `.text`, `.image(URL)` or `.systemImage`. |
| `.markdownAnimatesImages(_:)` | Turn animated image playback on or off. |
| `.markdownParseOptions(_:)` | Turn math or emoji recognition on or off. |
| `.markdownTextRenderer(.coreText / .swiftUIText)` | See *Text rendering*. |
| `.markdownStreamingCursor(_:)` | Show or hide the cursor while streaming. |
| `.onMarkdownLinkTap { url in .handled }` | Handle link taps (text and tables). |
| `.markdownSynchronousPreparationLimit(_:)` | Size threshold for synchronous preparation on first display. |
| `MarkdownPrefetcher.prefetch(_:width:…)` | Warm the cache imperatively. |
| `MarkdownCache.shared.removeAll()` | Free caches (for example on memory warnings). |

### Text rendering

By default, text blocks are typeset with CoreText (off the main thread when the width is known) and drawn in a
SwiftUI `Canvas`. Laying out a rich paragraph this way is about 8× cheaper than with SwiftUI `Text`. If you need
native text selection, use `.markdownTextRenderer(.swiftUIText)` together with `.textSelection(.enabled)`. It
costs more main-thread layout time.

## Architecture

```
String ─► Parser ─────────────► MarkdownDocument ─► Preparer ──────────────────────────► PreparedDocument ─► SwiftUI
          swift-markdown         Sendable IR         attributed strings, CoreText layout,   cached by content,
          + math/emoji pre-pass  stable block IDs    highlighted code, math bitmaps          theme, Dynamic Type
          incremental (stream)                       (parallel, off the main thread)
```

- **Parsing** (`Sources/MarkdownKit/Parsing`): a byte-level pre-pass pulls out math so cmark doesn't interpret
  `_`, `*`, `\` or `|` inside formulas. `IncrementalParser` freezes every top-level block except the last and
  re-parses only the tail.
- **Preparation** (`Preparation`, `Highlighting`, `Math`): per-block caching keyed by content and theme.
  Expensive blocks (tables, large code) are prepared in parallel. Table cells and code chunks have their own
  caches, so streaming tables and code only redo new rows or lines.
- **Views** (`Views`): blocks are `Equatable` views (unchanged blocks are skipped while streaming). Text,
  tables and code are drawn with CoreText inside `Canvas`, sized by a custom `Layout` from memoized layouts.
- Parser and math renderer sit behind internal protocols (`MarkdownParsing`, `MathRendering`), so alternative
  implementations can be benchmarked side by side (`MarkdownParserKind`, `MathRendererKind`).

## Benchmarks

All tests, including benchmarks, use Swift Testing. Run the benchmarks in release mode:

```bash
swift test -c release --filter MarkdownKitBenchmarks
```

They print timing statistics and check budgets in optimized builds. Set `MARKDOWNKIT_BENCHMARK_OUTPUT=path`
to also write results to a file. Results on an M1 Pro (macOS 27, release build):

| Benchmark | Median | p95 / p99 | Budget |
|---|---:|---:|---:|
| Parse 10 KB chat message | 1.6 ms | 2.0 ms | 5 ms |
| Parse 100 KB chat message | 18.3 ms | 18.9 ms | 25 ms |
| Parse 1 MB chat message | 242 ms | 243 ms | 250 ms |
| Parse 176 KB doc with **10 tables of 30×30** | 53.3 ms | 54.5 ms | 60 ms |
| Parse + prepare that doc, cold caches | 120 ms | 123 ms | 150 ms |
| Lay out one 30×30 table, cold | 8.1 ms | 8.9 ms | 15 ms |
| Cache hit for a prepared document | 0.008 ms | 0.008 ms | 0.5 ms |
| Streaming update, 30 KB message, 4 chars/update | 0.08 ms | p99 0.33 ms | p99 4 ms |
| Streaming update, 100 KB message (cost stays flat) | 0.08 ms | p99 0.27 ms | — |
| Streaming update, growing 30×30 tables (off main) | 2.9 ms | p99 6.3 ms | p99 16 ms |
| Tokenize 5,000 lines of Swift | 1.8 ms | 1.9 ms | 25 ms |
| Highlight 5,000 lines of Swift into chunks, cold | 57.6 ms | 59.4 ms | 120 ms |
| Render 300 formulas, cold | 160 ms | 161 ms | 400 ms |
| SwiftUI layout of one block (lazy-row path) | 0.66 ms | p95 1.9 ms | p95 4 ms |
| SwiftUI first layout of a 2–8 KB message, prefetched | 13.6 ms | 20.5 ms | 16 ms (median) |
| SwiftUI first layout of a doc with 10 tables of 30×30 | 21.6 ms | 22.7 ms | 33 ms |
| 30×30 table: Canvas tiles vs SwiftUI `Grid` | 1.9 ms vs 142 ms | — | faster than `Grid` |
| Streaming re-layout of a 20 KB message (main thread) | 3.4 ms | p95 6.2 ms | p95 8 ms |

### Scroll smoothness

The demo app's **Benchmark** tab auto-scrolls the 200-message transcript at 2,500 pt/s for 12 seconds and
reports the hitch time ratio: milliseconds of hitch per second of scrolling, as in Instruments (under 5 is good,
over 10 is critical). Launch arguments select variants (`-autorun YES -baseline YES -flatten NO -notables YES
-nocode YES -nomath YES -noimages YES -plain YES -renderer text`).

iPhone 17 Pro **simulator** (iOS 26.3, release build, M1 Pro host), prefetched:

| Content | Hitch ratio |
|---|---:|
| Baseline: 200 plain SwiftUI `Text` rows (no Markdown) | ~9 ms/s |
| `MarkdownBlocks`, prose only (headings, paragraphs, links) | ~13–17 ms/s |
| `MarkdownBlocks`, full transcript (30×30 tables, code, math, GIFs, lists, quotes) | ~50–60 ms/s |
| One `MarkdownView` per message, full transcript | ~70–80 ms/s |
| Full transcript with the SwiftUI `Text` renderer | ~71 ms/s |

What the profiling showed: parsing, preparation and our drawing code account for about 1% of main-thread
samples while scrolling. The remaining cost is SwiftUI and Core Animation commit work when rows appear. Each
additional view and layer per block (list items, quotes, table tiles, animated images) adds to it. Simulator
numbers are noisy (±5 ms/s) and don't represent device GPU or CPU, so **measure on a device** before drawing
conclusions. Shrinking the per-row view and layer count further is the main remaining performance work (see
*Status*).

## Demo app

`Examples/MarkdownKitDemo/MarkdownKitDemo.xcodeproj` (iOS and macOS) has these tabs:

- **Chat**: 200 messages, including 30×30 tables.
- **Streaming**: simulated token stream with adjustable speed.
- **Gallery**: every supported construct.
- **Benchmark**: the scroll-hitch meter described above.
- **Settings**: renderer, code theme, Dynamic Type, block rows.

The demo generates its animated images locally, so it needs no network access.

## Status and known limitations

- **Baseline tag**: `baseline-swift-markdown-swiftmath` marks this version, built on swift-markdown and
  SwiftMath, for comparison with future alternative implementations. Parse and math budgets pass, and the
  scroll profile shows the bottleneck is in SwiftUI rendering, not in those dependencies. So no replacement
  parser or math renderer was written.
- Scroll smoothness for content-heavy transcripts in the simulator is still above the 5 ms/s "good" threshold
  (see above). It hasn't been measured on a physical device yet.
- With the default CoreText renderer, text isn't selectable. Use `.swiftUIText` to get selection.
- Copying is per block: the code block copy button and the table context menu.
- Right-to-left paragraphs are right-aligned using a first-strong-character heuristic.
- The iOS 26.3 simulator runtime used in development is missing its color emoji font. Emoji show as ⍰ there,
  even in plain SwiftUI `Text`. This doesn't affect devices.
