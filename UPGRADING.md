# Upgrading to rubbs 1.0

1.0 is the cleanup release: one way to do each thing. Dead code is gone, the
colours come from one palette, every "pick one" is a `BBS::Selector`, there
is one word-wrap, one PETSCII glyph table, one telnet parser, and the
gateway refuses non-public addresses unless told otherwise. This file lists
every removed or changed API with its replacement and a grep that finds the
old use.

Run the greps from the board's root:

```sh
grep -rnE '<pattern>' lib bbs.rb test
```

## What most boards have to change

These three are all a board needs on 1.0, as far as the 11 TTG boards go.

### 1. `Screen#say` and `Screen#rule`: the colour is a keyword

```ruby
@screen.say('Posted.', GN)          # 0.x
@screen.say('Posted.', color: GN)   # 1.0
screen.rule(DG)    →   screen.rule(color: DG)
```

Grep: `\bsay\([^)]*, *[A-Z]` (and calls broken over two lines: `say\(`).
A Perl one-liner does the plain cases (the colour a constant):

```sh
perl -0pi -e 's/\b(say|rule)\(((?:[^()]|(\((?:[^()]++|(?3))*\)))*?),\s*([A-Z]\w*(?:::[A-Z]\w*)*)\s*\)/$1($2, color: $4)/g' $(find lib -name '*.rb')
```

A colour that is an expression (`color`, `ok ? GN : RD`) is a hand edit:
`say(text, color: color)`. Your own methods named `say` (a chat service's
`say(name, text)`) are not the Screen's: leave them.

### 2. `Screen#editor` is gone: use `Screen#edit`

```ruby
text = @screen.editor(MAX, 'WRITE A LETTER')                 # 0.x
text = @screen.edit(title: 'WRITE A LETTER', max: MAX).to_s  # 1.0
@screen.title('WRITE A LETTER')                              # what #editor did after
```

`#edit` returns `nil` when the caller quits (hence `.to_s`), draws at the
screen's own size, and leaves the screen as the editor left it. Grep:
`\.editor\(`.

### 3. `Petscii::Screen::MENU` is gone: the Selector's colours are the default

The menus of a Screen were coloured `Screen::MENU`, a copy of the Selector's
defaults. Now the Selector's default *is* the palette.

```ruby
FULL = MENU.merge(hint: "#{CY}#{RV}")                  # 0.x
FULL = BBS::Selector::COLORS.merge(hint: "#{CY}#{RV}") # 1.0
BBS::Selector.new(…, colors: MENU)  →  BBS::Selector.new(…)
```

Grep: `\bMENU\b` (your own `MENU` constants are fine).

### 4. A gateway to a neighbour board: `public_only: false`

`BBS::Gateway.new` now resolves the host once, refuses an address that is
not public (`BBS::Address.public?`: loopback, private, link-local, CGNAT,
ULA …) and connects to the vetted IP. A refused call ends with
`BBS::Gateway::Refused` in the report and "<name> may not be called from
here." on the caller's screen. A board that dials its own neighbours
(`host.docker.internal`, a container name, a private IP) says so:

```ruby
BBS::Gateway.new(host: 'host.docker.internal', port: 2327, name: 'Feedia', public_only: false)
```

Grep: `Gateway\.new`.

### 5. `Text.clean(keep_newlines: false)` no longer glues words

A line end becomes a space: `"a\rb"` is `"a b"`, not `"ab"`. For one line of
text use the new `BBS::Text.line(text)` (clean, whitespace runs to one
space, stripped). Grep: `keep_newlines: false` (and tests that expected glued
words).

## Removed: dead code nobody used

| Removed | Replacement |
|---|---|
| `BBS::TUI`, `BBS::TUIRunner`, the Flow's `tui` step | `BBS::Application`, or a `Petscii::Screen` for a line board |
| `BBS::Color` (`Color.c(:yellow, text)`) | the palette: `"#{BBS::Ansi::YELLOW}#{text}#{BBS::Ansi::RESET}"` |
| `Widgets::ProgressBar`, `Spinner`, `HBox`, `VBox`, `Panel` | lay widgets out in a `BBS::Window` |
| `Widgets::AnsiArt` (and `AnsiArt.view`) | `BBS::Art` + `Widgets::Scene` |
| `Menubar#add_menu`, `Menubar::MenuBuilder` | the Application's `menubar do menu('&File') { item … } end` |
| Flow steps `set`, `line`, `section`, `rows`, `table`, `wait_enter`, `fetch`, `pick`, `body`, `output`, `os` | a `call` step (`call { \|ctx, runner\| … }`); a FakeOS runs as a `BBS::Door` |
| Flow styles `:confirm :cyan :magenta :blue :yellow :white :green :red` | `:success :muted :error :info :prompt` |
| `FlowRunner::ERASE_LINE_ABOVE`, `NUMBER`, `EMAIL` | `Flow::Steps::EMAIL` |
| `Terminal.choose` (public) | `Terminal.flow` (the question is the private `Terminal::Question`) |
| `Petscii::Screen.plain` | `BBS::Petscii.plain` |
| `Dialogs.wrap`, `FrameBuffer::ANSI_ESC_RE`, `WRAP_TOKEN_RE`, `BLANK_RE` | `FrameBuffer.wrap_ansi` (the one wrap), `FrameBuffer.plain`, `Ansi::CSI_RE` |
| `FrameBuffer#write_ansi(…, cursor: true)` | nothing: only the TUI used it |
| `Patterns::MARKDOWN_LINK`, `MARKDOWN_MARK`, `LINE_BREAKS` | `BBS::Markdown.to_lines` renders Markdown |
| `Petscii::KEY_*`, `Petscii::SHIFT_SPACE` | `Petscii::KEYS` (byte → key), `Petscii.key(byte)` |
| `Petscii::SGR_*`, `Petscii::ANSI_WHITE` | inside `Petscii::Encoder` (`Encoder::Sgr`) |
| `CanvasMenu::COLORS` | `Selector::COLORS` (the roles; a canvas turns them into C64 codes) |
| `BlockFont::REVERSE`, `NORMAL`, `PETSCII_RESET`, `RESET`; `Editor::REVERSE`, `REVERSE_OFF` | `Ansi::REVERSE`, `Ansi::REVERSE_OFF`, `Ansi::GREY`, `Ansi::RESET` |
| Theme roles `check_on`, `check_off`, `listbox_header`, `warning`, `reset` | nothing drew with them; `Theme::ROLES` lists the roles |
| `Text::LINE_CONTROLS`, `Store::CONTROL_CHARS` | `Text::CONTROLS` |
| `Markdown.inline`, `item_body`, `split_row`, `separator_row?`, `parse_aligns`, `render_table`, `fit_cell` | `Markdown.to_lines` |
| `Windows::Form#clear_status` | `form.info('')` |
| `ButtonBar.button_width`, `ButtonBar.build_handler` (now private) | `ButtonBar.attach`, `ButtonBar.place` |
| `Menubar#navigate`, `#open_via_keyboard` (now private), `Menubar#open_index` | `Menubar#handle_event`, `#opened_menu`, `#open?` |
| `Window#title_click?`, `corner?`, `start_drag`, `drag`, `keyboard_move`, `hotkey_button`, `zoom_x` (now private) | `Window#handle_event` |
| `Application::Builder#init_block`, `menubar_block`, `statusbar_hints`, `helper_module`, `window_specs`, `doors` (readers) | the Application's own `window_specs` and `doors` |
| `WindowSpec#open_info`, `open_form`, `open_master_detail`, `open_stream` | `WindowSpec#open(app, **extras)` |
| `Telnet::MOUSE_SHIFT`, `MOUSE_META`, `MOUSE_CTRL` | `Telnet::MOUSE_MODIFIERS` |
| `Gateway::Link::AGREE`, `TTYPE`, `TTYPE_SEND`, `TTYPE_IS`, `BYTE_MASK` | `Gateway::Negotiation` |
| `Zmodem::Sender#push`, `#stream` | `Zmodem.send_files` (internals: `Zmodem::Input`, `Output`, `Stream`) |

Grep for the lot:

```sh
grep -rnE 'BBS::(TUI|Color)\b|TUIRunner|ProgressBar|Spinner|HBox|VBox|Widgets::Panel|AnsiArt|add_menu|MenuBuilder|Terminal\.choose|Screen\.plain|Dialogs\.wrap|ANSI_ESC_RE|WRAP_TOKEN_RE|Patterns::MARKDOWN|Petscii::(KEY_|SGR_|SHIFT_SPACE)|CanvasMenu::COLORS|BlockFont::(REVERSE|NORMAL|PETSCII_RESET|RESET)|Editor::REVERSE|check_on|check_off|listbox_header|LINE_CONTROLS|CONTROL_CHARS|clear_status|open_index|MOUSE_(SHIFT|META|CTRL)\b' lib bbs.rb test
```

## Changed behaviour

- **The Flow's `menu` is a `BBS::Selector`**: numbered, the cursor keys and
  the digits light an option, RETURN takes it, Esc (RUN/STOP, ←) leaves the
  menu. The prompt stands on the menu's status row. The steps of an option
  run as before; `exit_menu` leaves.
- **Flow steps are objects** (`BBS::Flow::Steps`): `flow.steps` holds them,
  not Hashes. A `call` block gets the runner, which now also answers
  `context`, `ask(prompt)`, `select(options, hint:)`, `line(text, style:)`.
- **The palette**: `BBS::Ansi` has the colours (`GREY DIM_GREY DARK_GREY
  WHITE BRIGHT_RED GREEN BRIGHT_GREEN YELLOW BRIGHT_YELLOW BLUE BRIGHT_BLUE
  MAGENTA CYAN BRIGHT_CYAN`); `Petscii::Colors` (`WH YE CY …`) are their C64
  names, the same sequences as before. `Canvas.color` takes a palette colour
  too (`Canvas.color(YE) == Canvas::YELLOW`).
- **`Ansi::CSI_RE` matches `?` parameters** (`\e[?25l`), so `FrameBuffer.plain`,
  `visible_width` and `clip_ansi` treat a private-mode sequence as a
  sequence, not as text.
- **Themes**: `Theme::PRESETS` is a Hash of Hashes, `Theme.fetch(name)` the
  one constructor (`Theme.synchronet` … are shorthands for it), and a Theme is
  frozen. `Theme.new` and `#merge` raise ArgumentError for a role outside
  `Theme::ROLES`.
- **PETSCII glyphs**: one table. The rounded corners `╭╮╰╯` are
  `Petscii::ROUNDED_CORNERS` (0xd5, 0xc9, 0xca, 0xcb, the uppercase/graphics
  set; a `Canvas` draws them); the lowercase set (a session's Encoder) shows
  them as the square box corners `┌┐└┘` (0xb0, 0xae, 0xad, 0xbd). The Encoder
  now also draws the quarter blocks `▖▗▘▝▚`. `Canvas::GLYPHS` has the square
  box drawing too (`┌ ├ ┬ …`).
- **Logging**: the library writes `"<log_tag>: <tag>: <message>"` to stderr
  through `BBS.log` (the lines used to start `BBS session error:`,
  `BBS door x:`, `BBS::AI:`, `BBS gateway`, `BBS::Store:`, `BBS call error:`,
  `BBS event error:`). Set `c.log_tag = '<slug>-bbs'` (or `BBS_LOG_TAG`).
  "BBS busy" and "BBS crowded" are still in their lines. A
  `DiscordWebhook`'s `label:` is now the log tag: drop the board's slug from
  it.
- **`Telnet#settle`** returns the session or `nil` (was true/false).
- **`FocusManager#handle_focus_key`** returns `:handled` or `nil` (was
  true/false); **`TextBuffer#edit`** the buffer or `nil`.
- **`Windows::Form`, `Info`, `MasterDetail`, `Stream`** take their required
  keywords plus options checked against `OPTIONS` (same names and defaults;
  an unknown option still raises). `Form`'s `on_submit:` is optional.
- **A statusbar click** only reaches the hints drawn on the bar.
- **`Store`** imports a CSV with broken rows: they go to `<csv>.rejected` and
  a log line, the rest are imported. `Store#open!` imports at boot.

## New in 1.0 (optional to adopt)

- `BBS.log(tag, message)`, `Config#log_tag`.
- `BBS.background(name, every: nil, retry_after: 5, max_retry: 300) { … }`
  (and `BBS::Background`): a thread with logging and retry with backoff, for
  the index loaded at boot, the catalog refreshed every hour.
- `BBS::Wikipedia.new(user_agent:, rate: 5)#get(lang, **params)`: the paced
  Action API client of alexandria and commodex (drop their
  `wikipedia_client.rb`; it returns the parsed Hash and raises
  `BBS::HTTP::Error`).
- `BBS::RateLimit.allow_all?([[limit, key], …])`: several limits at once,
  counted in all or none; `#room?` / `#record` to check and count apart;
  `RateLimit.new(limit:, per:, store: db, name:)` keeps the counters in a
  `BBS::SQLite` table, so a login lockout survives a restart.
- `BBS::Text.line(text)`.
- `BBS::HTTP::TooLarge`, `BBS::HTTP.get(url, to: io)` (the body streamed to an
  IO, capped).
- `BBS::Cache#refresh(key) { … }`: the value replaced only when the block
  succeeds.
- `BBS::Telnet::Parser`: the one telnet IAC parser (the line and both
  directions of a gateway).
- The error rule (README, "Where an error is handled"): repositories raise
  `BBS::HTTP::Error` or a domain error; services rescue it, log it once with
  `BBS.log` and decide what the caller sees; the UI never rescues
  `HTTP::Error`.

## The TTG boards, file by file

What breaks on 1.0, as found by running each board's tests and booting it
(both faces) against 1.0. Lines are those of the boards' commits of 2026-11-01/02, before
the upgrade.

| Board | Change |
|---|---|
| alexandria-bbs | `lib/ui/petscii.rb:76` say → `color:` |
| commodex-bbs | `lib/ui/petscii/board.rb:60, 69, 87, 127, 143, 144, 151, 157` say → `color:` (157 is `result == :ok ? GN : RD`, by hand) |
| feedia-bbs | `lib/ui/petscii.rb:100, 148, 164, 177–180` say → `color:`; `:168` `editor` → `edit` (§2) |
| impostor-bbs | `lib/ui/petscii.rb:35` say → `color:`. The debrief menu is now a Selector (no code change). |
| pixelia-bbs | `lib/ui/petscii/canvas.rb:158, 167, 176`, `lib/ui/petscii/gallery.rb:133` say → `color:` |
| scriptorium-bbs | `lib/ui/petscii.rb:100, 123, 145` say → `color:` |
| teletype-bbs | `lib/ui/petscii.rb:59, 79, 86, 109, 142`; `lib/ui/petscii/messages.rb:62, 63, 64, 124, 143, 159, 161, 183, 200, 218, 221, 244` (221 is `irc.joined? ? GR : RD`, by hand); `lib/ui/petscii/more.rb:41, 53, 62`; `lib/ui/petscii/people.rb:130, 132, 180, 185, 189, 204, 206` say → `color:`. `lib/ui/petscii/messages.rb:58, 133` `editor` → `edit` (§2). (`chat.say` in `messages.rb:202` and `modern/windows/chat.rb` are the chat's own, leave them.) |
| ttg-blog-bbs | `lib/ui/petscii/screen.rb:12` `MENU.merge` → `BBS::Selector::COLORS.merge`, `:84` drop `colors: MENU` (§3; the board does not load without it). `lib/ui/screen.rb:19, 26` `say(x, color)` → `say(x, color: color)` (by hand), `:34`; `lib/ui/board.rb:122, 128`; `lib/ui/board/account.rb:24, 43, 46, 58, 72, 73, 74`; `lib/ui/board/composer.rb:88` say → `color:`. `test/post_service_test.rb:12` expects `'a b'` for the summary `"a\rb\u0085"` (§5). |
| ttg-gate-bbs | `lib/ui/dial.rb:9` (`UI.dial`, the own boards on `host.docker.internal`): add `public_only: false` (§4), or every own-board dial is refused. `dial_catalog` (`:20`) keeps the default: it dials the vetted public `call.ip`. |
| warp-engine-bbs | `lib/ui/petscii.rb:93, 136, 146` say → `color:` (146 is `say(text, color)`, by hand) |
| wiki-bbs | `lib/ui/petscii.rb:39`, `lib/ui/petscii/browser.rb:91, 92, 97, 114, 122, 123, 124, 131, 134, 135` say → `color:` |

Nothing else in the boards uses an API that 1.0 removed. With these edits
every board's test suite passes and both faces boot and answer.
