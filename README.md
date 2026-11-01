# rubbs

A Ruby gem for building telnet BBS servers. From a one-screen line prompt to
a full-blown Synchronet-style multi-window application — without leaving Ruby.

```ruby
require 'bbs'

BBS.configure do |c|
  c.flow = BBS::Flow.define do
    big_banner 'My BBS'
    ask :name, prompt: 'Your name'
    say 'Welcome!', style: :success
  end
end

BBS.start
```

Connect with `telnet localhost 2323`.

---

## Table of contents

1. [Concepts](#1-concepts)
2. [Installation & quick start](#2-installation--quick-start)
3. [Server lifecycle](#3-server-lifecycle)
4. [The Flow layer](#4-the-flow-layer)
5. [The TUI layer](#5-the-tui-layer)
6. [The Application layer](#6-the-application-layer)
7. [Widgets](#7-widgets)
8. [Windows](#8-windows)
9. [Pre-built window types (`BBS::Windows`)](#9-pre-built-window-types-bbswindows)
10. [Dialogs](#10-dialogs)
11. [Menubar, Statusbar, Focus](#11-menubar-statusbar-focus)
12. [Theming](#12-theming)
13. [FrameBuffer & drawing primitives](#13-framebuffer--drawing-primitives)
14. [Markdown renderer](#14-markdown-renderer)
15. [Banner, ASCII art & ERB screens](#15-banner-ascii-art--erb-screens)
16. [Persistence (`BBS::Store`)](#16-persistence-bbsstore)
17. [AI characters (`BBS::AI`)](#17-ai-characters-bbsai)
18. [Doors (`BBS::Door`)](#18-doors-bbsdoor) — telnet gateways (`BBS::Gateway`) and file downloads (`BBS::Zmodem`, `BBS::Xmodem`)
19. [Telnet, sessions & input model](#19-telnet-sessions--input-model)
20. [Source layout](#20-source-layout)

---

## 1. Concepts

rubbs ships three interaction layers, from simplest to richest. Layers can be
mixed in a single session — typically `Flow` for login, then `Application`
for the main shell.

| Layer | What it is | When to use |
|---|---|---|
| `BBS::Flow` | Line-oriented declarative dialogue (ask / say / menu / persist) | Login, registration, simple wizards |
| `BBS::TUI` | Single-screen page router with frame-buffer delta rendering | Single-purpose full-screen UIs |
| `BBS::Application` | Widget framework: Menubar, Window, Button, TextInput, ListBox, … | Multi-window Synchronet-style BBSes |

Four building blocks sit beside them:

| Block | What it is | When to use |
|---|---|---|
| `BBS::FakeOS` | A character-mode OS simulator: boot script + command shell | A simulated machine the caller types into |
| `BBS::Door` | Hands the line from an Application to a program and back | Games, simulated machines, anything full-line inside a menu-driven BBS |
| `BBS::AI` | A persona-driven chat with a small model, streamed to the terminal | A character the caller can talk to, e.g. in a FakeOS `on_unknown` |
| `BBS::Petscii` | A Commodore 64 on the line: PETSCII out, the C64's keys in (`session.petscii!`) | A PETSCII face of a board, on the same Flows and doors |
| `BBS::Terminal` | The first question of a two-faced board: modern (ANSI/xterm) or PETSCII (a C64) | One port for both faces (`Terminal.flow`) |

The server boots a Telnet TCP listener, hands each connection a `Session`,
which runs the configured `Flow`. Inside that flow you can hand off to a
`TUI` or `Application`, then return to the flow when the user exits.

```
TCPServer → Session → FlowRunner ─┬→ TUIRunner
                                  ├→ Application#run ⇄ Door#run (FakeOS, …)
                                  └→ FlowRunner (sub-flow, e.g. confirm-block)
```

---

## 2. Installation & quick start

### Gemfile

```ruby
gem 'bbs', git: 'https://git.teletypegames.org/engines/rubbs.git'
```

### Hello world — Flow only

```ruby
require 'bbs'

BBS.configure do |c|
  c.flow = BBS::Flow.define do
    big_banner 'MY BBS', style: :success
    ask :name, prompt: 'Name'
    say 'Welcome!', style: :success
  end
end

BBS.start
```

### Flow → Application

```ruby
require 'bbs'

MAIN = BBS::Application.define do
  theme BBS::Theme.synchronet
  menubar do
    menu '&File' do
      item '&About' do BBS::Dialogs.message(self, 'Hello from rubbs!') end
      item 'E&xit'  do :halt end
    end
  end
  status_hint('F1', 'Help')  { BBS::Dialogs.message(self, 'No help yet.') }
  status_hint('F10', 'Menu') { menubar.open(0) }
end

BBS.configure do |c|
  c.mouse        = true
  c.idle_seconds = 600
  c.flow = BBS::Flow.define do
    big_banner 'MY BBS'
    ask :username, prompt: 'Name'
    app MAIN
    say 'Goodbye!'
  end
end

BBS.start
```

---

## 3. Server lifecycle

### `BBS.configure { |c| … }` / `BBS.config`

`BBS::Config` is a value object accessed through these two singleton helpers.
The `Server` reads it once at boot; per-session state lives on `BBS::Session`.

| Field | Default | Description |
|---|---|---|
| `flow` | — | The root `BBS::Flow` to run for each connection (required). |
| `port` | `ENV["BBS_PORT"] \|\| 2323` | TCP port for `BBS::Server`. |
| `mouse` | `false` | If true, sessions enable xterm SGR mouse reporting on negotiate. |
| `mouse_on_connect` | `true` | With `mouse`, whether reporting starts on connect. `false` leaves it to the flow (`session.enable_mouse`), e.g. after asking whether the caller has a C64, which would print the escape sequence. Applications and doors still switch it on and off. |
| `idle_seconds` | `nil` | Hard idle-timeout of the Application loop and the TUI. It is also each connection's socket read/write timeout (900 s when `nil`), so a line that stays silent at a login prompt or inside a door is dropped too. Every session starts with this value; `session.idle_seconds = 3600` changes it for one caller (the loop and the socket timeout alike). |
| `max_sessions` | `ENV["BBS_MAX_SESSIONS"] \|\| 100` | Connections served at once; one more is told to try later and closed, and the server logs `BBS busy: …`. |
| `theme` | `nil` | Default `BBS::Theme` for Applications. |
| `screens_dir` | `nil` | Directory for ERB templates used by `Flow#screen`. |
| `on_session_end` | `nil` | `->(session) { … }` invoked from the server thread after each session ends, even on errors. |

### `BBS.start(port: …)`

Boots a `BBS::Server` (one thread per client). Each thread:
1. Creates a `BBS::Session` (assigns a hex `session_id`).
2. Performs Telnet negotiation (SGA, ECHO, NAWS — terminal size).
3. Enables mouse reporting if `BBS.config.mouse` (and `mouse_on_connect`).
4. Runs `FlowRunner.new(session, session_id, BBS.config.flow).run`.

### `BBS::Server`

Lightweight wrapper around `TCPServer`. Catches accept-loop errors
(`Errno::EMFILE`, `IOError`, …) and warns instead of crashing.

---

## 4. The Flow layer

`BBS::Flow.define { … }` builds an immutable, line-oriented dialogue. Each
step is interpreted by `BBS::FlowRunner` with access to a shared `@ctx` hash
keyed by Symbol field names.

### Step reference

| Step | Signature | Effect |
|---|---|---|
| `screen` | `screen :name, **vars` | Render `<name>.erb` from the flow's `screens_dir`, or from `BBS.config.screens_dir` (vars resolved against `@ctx` if Symbols). |
| `banner` | `banner text, style: :success` | Box-drawing banner. |
| `big_banner` | `big_banner text, style:, font:` | FIGlet (Artii) ASCII art header. `font:` defaults to `'slant'`. |
| `say` | `say text, style: :muted` | Print one line, then blank line. |
| `text` | `text content = nil, style:` / `text(style:) { ... }` | Print text; block receives `@ctx`. |
| `line` | `line color: :muted` | Horizontal rule. |
| `section` | `section title, color: :confirm` | "┌─ Title ─────┐" header. |
| `body` | `body(width:, indent:) { ... }` | Word-wrapped paragraph body; block returns Markdown-ish text. |
| `rows` | `rows(empty:) { ... }` | Block returns rows (strings or arrays) printed one per line. |
| `table` | `table { ... }` | Block returns `[[label, value], …]`; printed as label/value pairs. |
| `output` | `output { ... }` | Raw write; block returns a String written verbatim. |
| `set` | `set :name, value` | Assign `@ctx[name]`. |
| `ask` | `ask :name, prompt:, transform:, validate:` | Read line into `@ctx[:name]`. `transform` is `:upcase`/`:downcase`/`Proc`. `validate` is `:email`/`:non_empty`. |
| `persist` | `persist :a, :b, store: STORE` | Upsert listed fields into a `BBS::Store`, keyed by `session_id`. |
| `pause` | `pause msg, seconds: 1.0` | Print message and sleep. |
| `wait_enter` | `wait_enter prompt:` | Block until ENTER. |
| `gate` | `gate(denied:) { \|ctx\| ... }` | If block returns falsy, print denied msg and halt. |
| `confirm` | `confirm msg, denied:` | Yes/No prompt; halt if "no". |
| `confirm` | `confirm(msg, denied:) { ... }` | Yes/No prompt; on "yes" run sub-flow. |
| `menu` | `menu(prompt, loop: false) { option … }` | Numbered options. Each option is a sub-flow; `loop: true` re-shows after each selection until `exit_menu`. |
| `exit_menu` | `exit_menu` | Return to the enclosing menu's caller. |
| `fetch` | `fetch :name, loading: 'Loading…' { \|ctx\| ... }` | Show spinner-style line, store block result into `@ctx[:name]`. |
| `pick` | `pick from:, prompt:, empty:, item:, hint:` | Show numbered list of `@ctx[from]`; on selection, store as `@ctx[:picked]` and run sub-flow. |
| `call` | `call { \|ctx, runner\| ... }` | Arbitrary code; runner exposes `write`/`readline(mask:)`/`session`. Return `:halt` to terminate. |
| `tui` | `tui DEFINITION` | Hand off to a `BBS::TUI`. |
| `app` | `app DEFINITION` | Hand off to a `BBS::Application`. |

### A flow's own screens

`BBS::Flow.define(screens_dir: path) { … }` keeps the flow's ERB screens
next to it, so a flow shipped in a gem renders its own `screen` steps
inside any BBS, whatever `BBS.config.screens_dir` says. Without it the
flow uses `BBS.config.screens_dir`.

`FlowRunner.new(session, session_id, flow, context: {})` seeds the flow's
context; a door uses it to pass the caller's name in.

### Available styles for `style:` arguments

`:success :muted :error :info :prompt :confirm :cyan :magenta :blue :yellow :white :green :red`

### Validation

`ask … validate: :email` rejects with a built-in message and halts. `:non_empty`
rejects empties. Pass a custom Proc for ad-hoc rules (must return truthy).

### Sub-flows

`menu`, `confirm { … }` and `pick { … }` open nested `Flow` blocks evaluated
on a fresh `Flow` instance and executed with the same `@ctx`.

### Example — login + menu

```ruby
BBS::Flow.define do
  screen :welcome, year: Time.now.year
  ask :user, prompt: 'Login', validate: :non_empty, transform: :downcase
  persist :user, store: USERS

  gate(denied: 'Banned user.') { |ctx| !banned?(ctx[:user]) }

  menu 'Choose:', loop: true do
    option 'Read messages' do
      fetch(:msgs) { |ctx| MsgStore.for(ctx[:user]) }
      pick from: :msgs, prompt: 'Pick #:', empty: 'No mail.',
           item: ->(m, i) { "#{i}. #{m.subject}" } do
        text { |ctx| ctx[:picked].body }
        wait_enter
      end
    end
    option 'Quit' do
      call { :halt }
    end
  end
end
```

---

## 5. The TUI layer

A single-screen page router with frame-buffer delta rendering. Use it when
you want a custom dashboard or interactive screen without the overhead of
the full widget framework.

```ruby
DASH = BBS::TUI.define do
  start :main

  init do
    @selection = 0
  end

  helpers do
    def palette = %w[red yellow green]
  end

  chrome do
    bar y: 1, content: ' my-bbs ', style: :info
    bar y: term_rows, content: ' F10=quit ', style: :muted
  end

  page :main do
    enter do
      @items = fetch_items
    end

    nav :menu, size: -> { @items.size }

    render do
      list @items, x: 4, y: 3, selected: @selection
    end

    key(:enter) { @selected = @items[@selection]; go :detail }
    key(:f10)   { :halt }
  end

  page :detail do
    nav :scroll, content: -> { @body }, window: -> { term_rows - 4 }

    enter { @scroll = 0; @body = render_body(@selected) }
    render do
      text @body.lines[@scroll, term_rows - 4]&.join, x: 2, y: 2
    end
    key(:escape) { go :main }
  end
end

# Inside a Flow:
BBS::Flow.define { tui DASH }
```

### `BBS::TUI.define`

| DSL method | Purpose |
|---|---|
| `start :page` | Initial page (default `:idle`). |
| `init { ... }` | Runs once before the first render, in the page context. |
| `chrome { ... }` | Drawn on every render, before the active page. |
| `helpers { ... }` | Module-eval'd; methods become callable inside pages. |
| `page :name { ... }` | Define a page. |

### `BBS::TUI::Page` DSL

| Method | Purpose |
|---|---|
| `enter { ... }` | Runs when entering the page (`go :name`). |
| `render { ... }` | Re-evaluated every paint. |
| `key(k) { ... }` | Bind a single key (Symbol or 1-char String). |
| `printable { \|ch\| ... }` | Catch printable chars without explicit binding. |
| `mouse { \|m\| ... }` | Mouse event handler. |
| `any_key { \|k\| ... }` | Catch-all fallback (after printable). |
| `nav :menu, size:` | Install up/down on `@menu_selection` (wraps). |
| `nav :cycle` | Up/down on `@item_selection` over `@items` (wraps). |
| `nav :list, window:` | Up/down/page-up/page-down/home/end on `@item_selection` + `@scroll` over `@items`. |
| `nav :scroll, content:, window:` | Same keys for `@scroll` over a content list (no selection). |

Block arguments to `nav` are `Proc`s evaluated inside the page context, e.g.
`window: -> { term_rows - 6 }`. Plain values are wrapped in a Proc.

Returning `:halt` from any binding ends the TUI.

### `BBS::TUIRunner::Context` — drawing primitives

Inside `chrome`/`enter`/`render`/keybindings the `self` is a Context with:

| Method | Purpose |
|---|---|
| `term_cols`, `term_rows` | Negotiated terminal size (NAWS). |
| `clear` | Wipe next frame. |
| `at(x, y)` | Position cursor. |
| `text(content, x:, y:, style:)` | Write a string (ANSI passthrough). |
| `bar(y:, content:, width:, style:)` | Full-width band of `style` with text. |
| `box(x:, y:, width:, height:, title:, style:, background:) { \|ix, iy, iw, ih\| ... }` | Double-line frame; yields inner area. |
| `float(title:, width:, height:, style:, background:) { ... }` | Centered `box`. |
| `fill(x:, y:, width:, height:, background:)` | Solid block. |
| `screen_fill(background:)` | Repaint whole screen background. |
| `list(items, x:, y:, selected:, style:, highlight:)` | Bullet list with optional selection marker. |
| `list_view(items, x:, y:, height:, scroll:, selected:, label:, hint:, hint_y:, empty:, style:, highlight:)` | Scrollable list with selected hint line. |
| `wordwrap(text, width)` | Strip simple Markdown and wrap. |
| `go(page)` | Switch page (calls its `enter`). |
| `reload` | Re-enter the current page. |

Both `style:` and `background:` accept either a `FlowRunner::STYLES` Symbol
(`:success`, `:prompt`, …) or a raw ANSI sequence. Background colors map
through `:black :red :green :yellow :blue :cyan :white`.

---

## 6. The Application layer

`BBS::Application` is the full TUI: a widget event loop with menubar, status
bar, a switchable window stack, mouse, focus traversal, themes and per-window ticks.

### Top-level build with `Application.define`

```ruby
MAIN = BBS::Application.define do
  theme :synchronet do
    accent "\e[1;33;40m"
  end

  services chat: ChatService.new, boards: BoardService.new

  helpers do
    def announce(text)
      BBS::Dialogs.message(self, text, title: ' Notice ')
    end
  end

  init do
    @user = context[:username]
  end

  body do
    add BBS::Widgets::Label.new(text: 'Background label', style_key: :text)
  end

  menubar do
    menu '&File' do
      item '&Quit', shortcut: 'Alt-X' do :halt end
    end
  end

  status_hint('F10', 'Menu')  { menubar.open(0) }
  status_hint('F1',  'Help')  { announce('No help yet') }

  window :compose, type: :form do |w|
    w.title 'Compose'
    w.field :body, type: :textarea
    w.on_submit { |values, form, ctx| ctx[:boards].post(values[:body]); :close }
  end
end
```

### `Application.define` DSL

| Method | Purpose |
|---|---|
| `theme(symbol_or_theme)` | Set the base theme (Symbol calls `BBS::Theme.<name>`; or pass a `Theme` instance). |
| `theme(:base) { ... }` | Inside the block, any one-arg method call (`screen "\e[40m"`) overrides that style key. Use `inherit :neumanntronics` to switch base mid-block. `style :key, "\e[…"` is also available. |
| `services(hash)` | Merge into the services hash exposed to window callbacks via `ctx`. Call multiple times to add more. |
| `helpers { ... }` | Module-eval'd; methods become available on the live `Application` instance. |
| `init { ... }` | Runs in the Application context after building, before `body`. |
| `body { ... }` | Block evaluated against a `BodyContext` — call `add(widget)` to attach widgets to the root container. |
| `menubar { menu '&X' do item '&Y' do … end end }` | Define the top menubar (see [§11](#11-menubar-statusbar-focus)). |
| `status_hint(key, label, hidden: false) { ... }` | Append one status bar hotkey hint. `hidden: true` keeps the key working without showing it (room for `right_text`). |
| `on_tick { ... }` | Runs in the Application context once a second while the caller is idle (a clock on `statusbar.right_text`, a counter). |
| `on_idle { ... }` | Runs in the Application context when the caller reaches the idle limit. Return `:keep` to keep them on (a "still there?" dialog that got an answer); anything else drops the line. |
| `on_door { \|door, context\| ... }` | Runs just before `Builder#run` hands the line to a door (who is where, a log line). |
| `window(:name, type: :info\|:form\|:master_detail\|:stream) { \|w\| ... }` | Register a declarative window spec (see [§9](#9-pre-built-window-types-bbswindows)). |
| `door(:name, program, label: nil, hint: nil)` | Declare a door the caller can step into (see [§18](#18-doors-bbsdoor)). Inside `menu`, `doors` adds one item per declared door, with its `hint` on the statusbar. |

### Application instance API

| Method | Purpose |
|---|---|
| `cols`, `rows` | Terminal size from NAWS (defaults 80×24). |
| `theme` / `services` / `context` | Live state. |
| `add(widget)` | Append to the root container. |
| `open_window(window)` | Push a `Window` onto the stack and make it the active one. |
| `open_window(:name, **extras)` | Open a registered `WindowSpec`; `extras` flow into the spec's `ctx`. |
| `raise_window(window)` | Bring an open window to the front and make it the active one. |
| `cycle_windows(step = 1)` | The next (or, with -1, the previous) switchable window to the front. |
| `close_window(window = top_window)` | Pop a window. Calls its `on_close` if any. |
| `top_window` | The active window, the target of input. |
| `with_loading(text) { ... }` | Show a "Please wait" modal while the block runs in a thread; returns the block's value. |
| `with_line { \|session\| ... }` | Hand the raw line to the block (a file transfer, say) on a clean screen without mouse reporting, then repaint everything; returns the block's value. |
| `tick!` | Manually fire the periodic tick. |
| `stop!` | Break out of the run loop. |
| `open_door(:name)` | Leave through a declared door: returns `:halt`, and `Builder#run` opens the door. |

### Run loop

`run` does:

1. Render full frame, diff against the committed buffer, write the delta.
2. Wait for a key (`Session#readkey(timeout: 1.0)`).
3. On `:idle` — fire `tick!` (which runs the `on_tick` block and `window.tick(self)`
   for every open window), then check the idle-disconnect timeout: at the
   session's `idle_seconds` the `on_idle` block runs, and unless it returns
   `:keep` the loop shows a message and ends.
4. Otherwise build an `Event` and dispatch (top window → menubar → statusbar
   → root focus manager).

Return `:halt` from any handler to end the application (and, via Flow, the
session). An exception in a handler is logged and the event dropped: it does
not end the caller's session.

`Builder#run(session:, session_id:, context:)` is `build(...).run` that also
takes the caller through doors: when the application ended with `open_door`,
it runs the door and builds the application again, until the caller leaves
without one.

---

## 7. Widgets

All widgets inherit from `BBS::Widget` (see `bbs/widget.rb`). They have:

```ruby
bounds     # Rect(x, y, width, height) — 1-based screen coords
parent     # enclosing Container
id         # optional Symbol (Container#find(:my_id))
visible    # default true
focused    # set by FocusManager
enabled    # default true
theme      # propagated by Container#theme=
```

Subclasses override `render(frame)` and `handle_event(event)`. Return values
from `handle_event`: `:halt` ends the app, `:handled` stops propagation, `nil`
continues.

### `Widgets::Label`
`text:`, `align:` (`:left`/`:center`/`:right`), `style_key:` (theme key,
default `:text`). Renders one line, clipped to width.

### `Widgets::Button`
`label:` (e.g. `'&Save'` — ampersand marks hotkey), `on_click: ->(btn) { … }`.
Enter/Space fires. Inside a window the hotkey letter fires it too, alone or
with Alt, unless the focused widget takes the key (a text field takes plain
letters, so there it is Alt+letter). Mouse-clickable. `enabled = false`
greys out.

### `Widgets::TextInput`
Single-line input. `value:`, `placeholder:`, `max_length:` (default 256),
`password:` (mask with `*`), `on_submit: ->(value, self) { … }`,
`on_change: ->(value, self) { … }`. Cursor with arrows / Home / End,
Backspace, Delete. Keys it has no use for (Esc, function keys, Alt+letter)
go on to the window, so Esc closes a window from inside its text field.

### `Widgets::TextArea`
Multi-line. `value:`, `max_length:` (default 8000), `on_change:`. Arrows
navigate across lines, Enter splits, Backspace joins, Home/End within line.
`value` returns `\n`-joined string.

### `Widgets::Checkbox`
`label:`, `checked:`, `on_change: ->(checked, self) { … }`. Toggle with
Space/Enter. Renders `[x] Label` / `[ ] Label`.

### `Widgets::ListBox`
Scrolling list. `items:` array, `label:` `->(item) { … }` (defaults
`item.to_s`), `on_select: ->(item, self) { … }` (selection change),
`on_activate: ->(item, self) { … }` (Enter / dbl-click). Up/Down, PgUp/PgDn,
Home/End, mouse click, mouse wheel scroll. `selected_item` exposes the
current row.

### `Widgets::ScrollView`
Read-only scrollable text. `lines:` is `Array<String>` (ANSI passthrough).
Up/Down/PgUp/PgDn/Home/End scrolls. Built-in right-side scrollbar.

### `Widgets::ProgressBar`
`value:`, `max:`, `label:`. Renders `██░░░` filled to ratio with optional
centered label.

### `Widgets::Spinner`
`label:` — braille spinner. Call `tick` to advance frame.

### Containers

`Container#add(child)`, `#remove`, `#clear`, `#find(id)`, `#walk { |w| … }`,
`#focusable_descendants`, `#hit_test(x, y)`. Theme propagates to children.

| Container | Purpose |
|---|---|
| `Widgets::HBox(gap: 1)` | Horizontal split. Equal widths, minus `gap` per child. |
| `Widgets::VBox(gap: 0)` | Vertical split. |
| `Widgets::Panel(title:, box_style: :single\|:double)` | Bordered container; `layout` gives each child the area inside the border; renders box first then children. |

### `Widgets::AnsiArt`

CP437 / ANSI-art viewer.

```ruby
art = BBS::Widgets::AnsiArt.from_file('art/welcome.ans',
                                       align: :center, valign: :middle)
art.layout(1, 2, 80, 22)
panel.add(art)

# Or a random pick from a directory:
BBS::Widgets::AnsiArt.random('art/')
BBS::Widgets::AnsiArt.from_string("hello", align: :left)
```

Constructors: `from_file(path, **opts)`, `from_string(text, **opts)`,
`random(dir, **opts)` (falls back to a built-in card if the dir is missing),
`default_lines` (the fallback card).

Encoding:
- `.ans` / `.asc` / `.nfo` → decoded as IBM437 → UTF-8.
- `.ansi` / `.txt` → assumed UTF-8.
- Anything else → UTF-8, falling back to IBM437.
- Trailing SAUCE metadata (`\x1A SAUCE…`) is stripped.

`AnsiArt.sauce(path)` reads that record: a `Sauce` struct with `title`,
`author`, `group` and `date` (`YYYY-MM-DD`), or `nil` when the file has none.

Options: `align: :left|:center|:right`, `valign: :top|:middle|:bottom`,
`fill_parent: true` (default — re-bounds to parent each render). The art is
placed as one block, by its widest line, so its lines keep their columns.

---

`AnsiArt.view(session, lines, title: nil)` shows art on the whole screen, the
way an art viewer of the old boards did: centred when it fits, scrolled with
the arrows, PgUp/PgDn and Home/End when it is taller than the screen, and a
status line with the title at the bottom; any other key or a click returns.
Run it inside `app.with_line { |session| … }`, which repaints the
application afterwards.

## 8. Windows

`BBS::Window < Container` — a top-level container with title bar, shadow,
close gadget, and its own `FocusManager`. Windows stack; the top one is the
active one and gets the input first, and the caller can switch between them
(see *Switching windows* below).

```ruby
win = BBS::Window.new(title: ' Inbox ', modal: false,
                      shadow: true, close_key: :escape,
                      on_close: ->(w) { puts 'closing' })
win.layout(10, 5, 60, 18)
win.add(some_widget)
win.reset_focus
app.open_window(win)
```

| Field | Default | Description |
|---|---|---|
| `title` | `nil` | Centered title in the top border. |
| `modal` | `false` | A modal window (the `Dialogs`) keeps the front until it closes: while one is open, no window switching. The other windows, the `BBS::Windows` types included, can be switched. |
| `shadow` | `true` | Draw the drop shadow. |
| `on_close` | `nil` | Called once when the window is closed (by `Application#close_window`); pass `false` to suppress the close gadget. |
| `close_key` | `:escape` | Key that triggers `close`. |
| `maximizable` | `false` | Give the window a zoom gadget, if it can lay itself out at any size (see below). |
| `movable` | `true` | Let the caller move the window and, when it is `resizable?`, size it (see below). |
| `accent` | `nil` | Set after `new`: a Hash of frame style roles drawn in other colours than the theme's (`window.accent = { window_border: "\e[0;38;5;78;48;5;16m" }`). Only the frame; the widgets inside keep the theme. |

Methods:

- `focus_manager` — lazy `FocusManager` over the window's children.
- `reset_focus` — rebuild the focus manager (call after adding widgets).
- `close` — return `:close_window`: the application pops the window and
  calls `on_close`.
- `tick(app)` — override in subclasses for per-second polling.

The close gadget `[■]` (top-left, columns x+2..x+4) is mouse-clickable.
Mouse-clicks elsewhere inside the window focus the hit widget.

### Maximizing

A window with `maximizable: true` (in the window DSL: `w.maximizable true`)
that is `resizable?` gets a zoom gadget in its top right corner, Turbo Vision
style: `[↑]` fills the desktop between the menubar and the statusbar
(`app.desktop_rect`), `[↕]` puts it back. **F5**, **Alt-Enter** and a
**double click on the title bar** do the same; `toggle_maximize` does it from
code and `maximized?` tells. A maximized window stays maximized when the
terminal is resized.

`resizable?` windows are `MasterDetail`, `Stream`, `Form` (a single textarea
without `:rows` takes the height left over) and an `Info` with `scroll: true`;
a static `Info` stays as it is, so `maximizable` has no effect on it. A custom
window joins in by returning true from `resizable?` and implementing
`normal_rect` (its usual `[x, y, w, h]`) and `place(x, y, w, h)` (lays its
children out at that size); `relayout` then picks one of them. Turn it on for
windows with a lot to read, not for small dialogs.

### Moving and sizing

A window that is not maximized can be moved, and a `resizable?` one sized
too; `movable: false` turns it off.

- **Mouse:** drag the title bar to move it, drag the bottom right corner
  (marked `┘`) to size it. Mouse reporting is xterm mode 1002, so the
  terminal reports the motion while the button is held.
- **Keyboard:** Ctrl-F5 starts it (F6 too, while the window is the only
  one: with more, F6 switches windows), Turbo Vision style, and the title
  bar shows the keys: the arrows move the window, Shift and the arrows size
  it, Tab switches the arrows between moving and sizing, Enter or Esc ends.
- `move_to(x, y, w, h)` does it from code. The window stays on the desktop
  and at least 24×7; once moved or sized it keeps that place when the
  terminal is resized (pulled back onto the screen if needed), and a
  restored maximized window goes back to it.

### Switching windows

Several windows can be open at once, and they cover each other in the
order they were last used, Turbo Vision style:

- **Mouse:** a click on a window behind the active one brings it to the
  front, and the click goes on to it: a button, the close gadget or a drag
  of its title bar answers at once.
- **Keyboard:** F6 brings the next window to the front, Shift-F6 the
  previous one; Alt-1 … Alt-9 picks a window by the number on the right of
  its top frame (each window gets the lowest free number when it opens).
- The active window has a double frame and a highlighted title, the others
  a single frame. When the active one closes, the one under it becomes
  active.
- A `modal` window (`Dialogs.message`, `confirm`, `input`) blocks all of
  it until it closes, so a question is always answered before anything
  else.
- `app.raise_window(win)` brings a window to the front from code,
  `app.cycle_windows(±1)` steps, `app.switchable_windows` lists them.

---

## 9. Pre-built window types (`BBS::Windows`)

Higher-level windows you can open imperatively with `.open(app, …)`, or
register declaratively with the window DSL.

### `BBS::Windows::Info`

Centered info / splash / message dialog.

```ruby
BBS::Windows::Info.open(app,
  title: ' Welcome ',
  width: 70, height: 20,
  body: [
    { text: 'rubbs v1.0', style: :accent, align: :center },
    :spacer,
    :rule,
    { kv: [['Online', '5'], ['Ruby', RUBY_VERSION]] },
    'Plain label line',
  ],
  buttons: [
    { label: '&Continue', primary: true },
    { label: '&Cancel',   cancel:  true, on_click: ->(w) { … } },
  ])
```

Body item types: `String` (label), `:spacer`/`''`/`nil` (blank row), `:rule`
(horizontal line), `{ text:, style:, align: }`, `{ kv: [[k,v],…], label_width: }`,
`{ widget:, height: }`, or a raw `BBS::Widget` (each used as-is, non-scroll mode).

`scroll: true` — flatten the whole body into a single `ScrollView`.

`padding:` overrides any of `{ sides: 2, top: 1, bottom: 2 }`.

Default buttons: a single centered `[ &Close ]` if `buttons:` is `nil`.
Pass `buttons: []` for none.

### `BBS::Windows::Form`

Labeled multi-row form with inline validation.

```ruby
BBS::Windows::Form.open(app,
  title: ' Profile ',
  hint:  'Edit your info:',
  fields: [
    { key: :name,    label: 'Name',     value: 'Joe', max_length: 80 },
    { key: :pw,      label: 'Password', value: '',    password: true },
    { key: :bio,     label: 'Bio',      type: :textarea, rows: 8 },
    { key: :public,  label: 'Public',   type: :checkbox, value: false },
  ],
  on_submit: ->(values, form) {
    return (form.error('Name is required.'); :keep) if values[:name].empty?
    User.save(values); :close
  },
  on_cancel: ->(form) { … })
```

Field types: `:input` (default, single-line `TextInput`), `:textarea`
(multi-line, label ignored), `:checkbox` (label part of widget).

Form methods callable from `on_submit`:

- `form.values` — current field values as a Hash.
- `form.error('msg')` — paint the status line red.
- `form.info('msg')` — paint the status line cyan-ish (input_label color).
- `form.clear_status` — wipe the status line.

Returning `:keep` from `on_submit` leaves the window open; any other return
closes it.

Buttons: a `[ &Save ]` / `[ &Cancel ]` pair by default. Override labels with
`submit_label:` / `cancel_label:`.

### `BBS::Windows::MasterDetail`

Two-pane browser: ListBox on the left, ScrollView on the right.

```ruby
BBS::Windows::MasterDetail.open(app,
  title: ' Game Catalog ',
  items: services[:games].all,
  item_label:    ->(g)     { g.title },
  render_detail: ->(g, w)  { GameCard.lines(g, w) },
  bottom_meta:   ->(g)     { "#{g.players} players  #{g.year}" },
  list_width: 30,
  empty_message: '  (no games)',
  actions: [
    { label: '&New', on_click: ->(win) { … } },
  ],
  close_label: '&Close')
```

`render_detail` is called whenever the selection changes; it receives
`(item, inner_width)` and returns an Array of ANSI-styled strings. Returning
nil shows nothing.

A `[ &Close ]` button is appended unless `close_button: false`. Other
`actions:` render to the left of close.

`on_activate: ->(item, window) { … }` runs when the caller presses Enter on a
list item. `replace_items(items, title: nil)` swaps the list in place and
selects the first item — a file browser changing folders. In the window DSL
the block is `w.on_activate { |item, window, ctx| … }`.

Exposes `list_widget`, `detail_view`, `meta_label` for live manipulation.

### `BBS::Windows::Stream`

Scrolling history pane + single-line input + idle-tick polling. Built for
chat / log views.

```ruby
BBS::Windows::Stream.open(app,
  title: ' Live Chat ',
  initial_lines: chat.history.map { format_line(_1) },
  placeholder: 'Type and press Enter…',
  buffer_size: 500,
  on_submit: ->(text, app) { chat.send(text); :keep },
  on_poll:   ->(app)       { chat.drain(app.session_id) })
```

`on_submit` is called when the user hits Enter on a non-empty line. Returning
`:keep` keeps the input as-is; otherwise the input is cleared.

`on_poll` is invoked from the 1 Hz idle tick. Return an Array of new lines
to append (or nil/[]).

`buffer_size:` caps the in-memory history (older lines drop off). Exposes
`history` (ScrollView) and `input` (TextInput).

### `BBS::Windows::ButtonBar`

Layout helper used by the other window types. Pass it a window, app and an
Array of button descriptors:

```ruby
BBS::Windows::ButtonBar.attach(window, app, [
  { key: :ok,     label: '&OK',     primary: true,
    on_click: ->(win) { … } },
  { key: :cancel, label: '&Cancel', cancel:  true, align: :left },
  { key: :help,   label: '&Help',   align: :left, keep_open: true,
    on_click: ->(win) { show_help } },
])
```

Returns `{ widgets:, primary:, by_key: }`. Default alignment is `:center` for
a single button, `:right` otherwise. `cancel: true` is informational (ESC
already closes via `Window#close_key`). `keep_open: true` keeps the window
open after click; otherwise it closes unless `on_click` returns `:keep`.

### Window DSL — `window :name, type: :form do |w| … end`

Inside `Application.define`, register a `WindowSpec` keyed by a name. Block
callbacks receive a `ctx` hash combining the app's services, app context,
and any extras passed to `open_window`.

```ruby
MAIN = BBS::Application.define do
  services boards: BoardService.new

  window :compose, type: :form do |w|
    w.title  { |ctx| " Post to #{ctx[:board].title} " }
    w.width  70
    w.field  :body, type: :textarea, max_length: 1000
    w.prefill { |ctx| { body: ctx[:draft]&.body || '' } }
    w.on_submit do |values, form, ctx|
      case ctx[:boards].post(ctx[:board].id, ctx[:username], values[:body])
      when :empty then form.error('Message cannot be empty.'); :keep
      else :close
      end
    end
  end
end

# Later:
app.open_window(:compose, board: current_board)
```

DSL inside the block:

| Attr / method | Applies to | Notes |
|---|---|---|
| `title`, `width`, `height`, `padding` | all | Scalar or `{ |ctx| ... }` block. |
| `accent` | all | A Hash of frame style roles (`window_border`, `window_title`, `window_title_focused`) in other colours than the theme's: the window's frame wears them, its widgets keep the theme. Mark which part of the board a window belongs to. |
| `body` | info | Array of body items. |
| `scroll`, `close_button`, `close_label` | info, master_detail, stream | |
| `button(**opts) { |win, ctx| ... }` | info | Custom buttons list. |
| `field key, **opts` | form | Field descriptor. |
| `prefill { |ctx| {...} }` | form | Pre-populate fields. |
| `hint`, `submit_label`, `cancel_label` | form | |
| `on_submit { |values, form, ctx| ... }` | form, stream | |
| `on_cancel { |form, ctx| ... }` | form | |
| `items { |ctx| ... }`, `item_label { |item, ctx| ... }` | master_detail | |
| `render_detail { |item, width, ctx| ... }` | master_detail | |
| `bottom_meta { |item, ctx| ... }` | master_detail | |
| `list_width`, `empty_message` | master_detail | |
| `action(**opts) { |win, ctx| ... }` | master_detail | Extra button. |
| `initial_lines { |ctx| ... }`, `placeholder`, `buffer_size` | stream | |
| `on_poll { |app, ctx| ... }` | stream | |

Block attrs that return blocks at the DSL level (`title { |ctx| … }`) are
re-evaluated each time the window opens, so they reflect the current `ctx`.

Open with `app.open_window(:name, key: value, …)`. Extras flow into `ctx`.

---

## 10. Dialogs

Quick imperative helpers in `BBS::Dialogs`:

```ruby
BBS::Dialogs.message(app, 'Saved!', title: ' Done ', width: 40)

BBS::Dialogs.confirm(app, 'Delete this message?',
  on_yes: -> { Msg.delete(id) },
  on_no:  -> { … })

BBS::Dialogs.input(app, prompt: 'New name:', value: '',
  on_submit: ->(value) { rename(value) })   # Enter in the field is OK
```

`BBS::Dialogs.centred_window(app, width:, height:, title:)` is the underlying
helper to build a centered, modal `Window`.

For richer windows prefer the `BBS::Windows::*` window types
described in [§9](#9-pre-built-window-types-bbswindows).

---

## 11. Menubar, Statusbar, Focus

### `BBS::Menubar`

```ruby
menubar do
  menu '&File' do
    item '&Open',    shortcut: 'Ctrl-O' do … end
    item '&Save',    shortcut: 'Ctrl-S', enabled: -> { current_doc } do … end
    separator
    item 'E&xit' do :halt end
  end
  menu '&Help' do
    item '&About' do BBS::Dialogs.message(self, 'rubbs') end
  end
end
```

- Ampersand in label marks the hotkey letter (Alt+letter from anywhere, plain
  letter while the menu is open).
- `shortcut:` is informational — it's drawn on the right of the menu item.
  Bind the actual shortcut via a `status_hint` or a custom key handler.
- `hint:` is a line about the item: while the item is highlighted, the
  statusbar shows it in place of its hints (`item '&News', hint: 'The latest
  releases' do … end`). A door's `hint:` (see `door`) does the same for its
  item in `doors`.
- F10 opens the first menu; ESC closes.
- Block `&block` runs in the Application's context (call `open_window`,
  `cols`, etc.). Returning `:halt` ends the session.

When the menubar is open, all events are routed to it first — its keys cannot
leak through to underlying windows.

### `BBS::Statusbar`

```ruby
status_hint('F10', 'Menu')   { menubar.open(0) }
status_hint('F1',  'Help')   { announce 'No help yet' }
status_hint('Alt-X', 'Quit') { :halt }
```

Renders left-aligned hints. While `statusbar.message` is set, the bar shows
that line instead, across its whole width; the Application sets it to the hint
of the highlighted menu item (`Menubar#selected_hint`) on every render.
Optional `statusbar.right_text = '...'` for a right-aligned indicator (set after build via `app.statusbar.right_text=`, in
`init` and again in `on_tick` for a clock).
Mouse-click on a hint fires its handler. Key matching is forgiving:
`F10` → `:f10`, `Alt-X` → `:alt_x`, `Esc` → `:escape`, `Tab` → `:tab`, anything
else uses case-insensitive name match.

### `BBS::FocusManager`

One per `Window` (and the application's root container). Walks visible,
enabled, focusable descendants for Tab / Shift-Tab cycling.

Key behavior:

- `handle_focus_key(event)` — consumes Tab / Shift-Tab.
- `focus(widget)` — explicit focus (used when a window opens to put cursor
  on the first input).
- `dispatch(event)` — forwards to the focused widget's `handle_event`.

---

## 12. Theming

A `BBS::Theme` is just a frozen Hash of role-name → ANSI SGR string.

Built-in presets:

| Preset | Vibe |
|---|---|
| `BBS::Theme.synchronet` (default) | Yellow on black, blue windows — Synchronet-style. |
| `BBS::Theme.nortoncommander` | Blue screen, cyan title bar — Norton Commander. |
| `BBS::Theme.dosnavigator` | Light grey background, white panels — DOS Navigator. |
| `BBS::Theme.neumanntronics` | Muted 256-color palette, dark cyan accents. |
| `BBS::Theme.mono` | Black & white, inverse-video selections — terminals without color. |

### Style keys

`screen`, `text`, `text_dim`, `text_bright`, `label`, `accent`, `success`,
`warning`, `error`,
`window_bg`, `window_border`, `window_title`, `window_title_focused`,
`window_text`, `window_shadow`,
`menubar`, `menubar_hotkey`, `menubar_selected`, `menubar_sel_hot`,
`menu_bg`, `menu_text`, `menu_hotkey`, `menu_selected`, `menu_disabled`,
`menu_border`,
`statusbar`, `statusbar_key`,
`button`, `button_focused`, `button_hotkey`, `button_disabled`,
`input`, `input_focused`, `input_label`,
`listbox`, `listbox_selected`, `listbox_focused`, `listbox_header`,
`scrollbar`, `scrollbar_thumb`,
`check_on`, `check_off`, `reset`.

### Customising

```ruby
# 1. Use a preset
theme BBS::Theme.synchronet

# 2. Override per-key with the DSL block
theme :nortoncommander do
  inherit :neumanntronics            # optional: switch base mid-block
  window_border "\e[1;36;44m"
  accent        "\e[1;33;44m"
  style :screen, "\e[40m"            # explicit form
end

# 3. Build from scratch
theme BBS::Theme.new(:mine, {
  screen: "\e[40m", text: "\e[0;37;40m", # …
})

# 4. Merge in code
custom = BBS::Theme.synchronet.merge(accent: "\e[1;36;40m")
```

`Theme#style(key)` / `Theme#[](key)` look up a SGR. Widgets call
`style(:role)` which resolves through the widget's `theme` or its parent's.

---

## 13. FrameBuffer & drawing primitives

`BBS::FrameBuffer` is the offscreen grid used by TUI and Application. Cells
hold `(char, sgr)` pairs; `diff` computes the minimal ANSI byte stream to
transform one frame into another (only changed cells get redrawn).

Direct API:

```ruby
fb = BBS::FrameBuffer.new(cols, rows)
fb.move(col, row)                              # 1-based
fb.write('Hello', sgr: "\e[1;33m")
fb.write_ansi("\e[1;33mbright\e[0m  normal")   # embedded SGR adds to base_sgr, a reset returns to it
fb.write_ansi(text, cursor: true)              # also honours \e[row;colH (TUI pages only)
fb.fill(x:, y:, width:, height:, sgr:, char: ' ')
fb.hline(x:, y:, length:, char: '─', sgr:)
fb.vline(x:, y:, length:, char: '│', sgr:)
fb.box(x:, y:, width:, height:, sgr:, fill_sgr:,
       style: :single|:double, title:, title_sgr:, title_indent:)
fb.shadow(x:, y:, width:, height:, sgr:)
delta = fb.diff(prev_fb)                       # ANSI byte stream
```

Class helpers for ANSI-aware string handling:

- `BBS::FrameBuffer.visible_width(text)` — length ignoring SGR escapes.
- `BBS::FrameBuffer.clip_ansi(text, max_width)` — truncate keeping styles intact.
- `BBS::FrameBuffer.wrap_ansi(text, width)` — word-wrap with SGR state
  carried across wrapped lines.

---

## 14. Markdown renderer

`BBS::Markdown.to_lines(text, width:, theme:)` → Array of ANSI strings,
one per terminal line. Feed it into a `BBS::Widgets::ScrollView` or an
`Info` window with `scroll: true`.

Supports:

- `#` … `######` headings (styled `text_bright`, `accent`, `label`).
- `**bold**`, `*italic*`, `_italic_`.
- `` `inline code` `` and ` ``` ` code blocks (preserved verbatim, no wrap).
- `[link text](url)` (renders `link text` in `accent`).
- `> quoted text` (rendered with a `│` gutter).
- `- ` / `* ` / `+ ` bullet lists, with hanging indents on wrap.
- `1. ` numbered lists.
- An indented line under a list item continues the item.
- `---` / `***` / `___` horizontal rules.
- Backslash escapes for `\* \_ \` \[ \( \{ \# …`.

Each inline span resets to `theme[:text]` so trailing text keeps the
correct background — critical when the surrounding window has a tinted
background.

---

## 15. Banner, ASCII art & ERB screens

### `BBS::Banner`

```ruby
BBS::Banner.render('Hello!',     color: "\e[1;32m", padding: 2)
BBS::Banner.render_big('ZINE',   color: "\e[1;36m", font: 'slant')
```

The plain variant draws a box-drawing banner; the big variant uses the
`artii` gem (FIGlet). Any Artii font name is accepted (`big`, `slant`,
`small`, etc.). These are used by Flow's `banner` / `big_banner` steps.

### `BBS::Renderer` — ERB screens

For `Flow#screen :name, **vars`:

```ruby
BBS.configure { |c| c.screens_dir = 'screens' }

# screens/welcome.erb
<%= clr %><%= banner 'Welcome' %>
   <%= green %>Hello <%= @username %>!<%= reset %>
```

The ERB context exposes color helpers (`green`, `yellow`, `cyan`, `white`,
`gray`, `red`, `dim_green`, `clr`, `reset`) plus `banner(text, padding:)`
and `big_banner(text, font:)`. Instance variables are populated from
`vars` (resolved against `@ctx` if the value is a Symbol).

### `BBS::Color`

Tiny helper for ad-hoc colorisation outside the theme system:

```ruby
include BBS::Color   # or BBS::Color.c(...)
c(:cyan, 'hello')    # => "\e[0;36mhello\e[0m"
```

Available colors: `:reset :gray :yellow :white :blue :cyan :green :magenta :red`.

---

## 16. Persistence (`BBS::Store`)

A thread-safe, upsert-by-`session_id` CSV file with an in-memory cache.
Used by `Flow#persist` but useful standalone.

```ruby
USERS = BBS::Store.new(
  path:    'data/users.csv',
  headers: %w[session_id timestamp username email]
)

USERS.upsert(session_id: sid, username: 'joe', email: 'j@e.com')
USERS.find(sid)        # => { 'session_id' => …, 'username' => 'joe', … } or nil
USERS.all              # => [ {…}, {…}, … ]
USERS.delete(sid)
```

- Headers `session_id` and `timestamp` are filled automatically when present.
- New rows append in O(1); updates rewrite the file under the mutex.
- `find` / `all` return Hashes.

---

## 17. AI characters (`BBS::AI`)

A character a caller can talk to: a persona read from a YAML file, a small
model behind any OpenAI-compatible chat endpoint (llama.cpp's `llama-server`,
Ollama, vLLM, a hosted API), a short memory per caller, and canned replies for
when the model is missing or fails. It fits a FakeOS `on_unknown` hook:

```ruby
PERSONA = BBS::AI::Persona.load('lib/oracle.yml')
ORACLE  = BBS::AI::Chat.new(
  persona: PERSONA,
  client:  BBS::AI::Client.new(url: ENV.fetch('ORACLE_LLM_URL', ''))
)

on_unknown do |input, io|
  out = BBS::AI::Typewriter.new(io, prefix: 'ORACLE: ', style: :dim)
  ORACLE.reply(input, io.ctx) { |piece| out.write(piece) }
  out.finish
end
```

The persona file:

```yaml
system: |                  # the system prompt
  You are the oracle of this board. …
examples:                  # turns in the right voice, sent before the history
  - user: hi
    assistant: I am here.
options:                   # extra request fields, e.g. sampling
  max_tokens: 96
  temperature: 0.4
  stop: ["\n\n"]           # a blank line ends the reply
deflect:                   # answered without the model, before it is asked
  - match: '\b(code|python)\b'
    reply: I do not write code.
fallback:                  # canned replies, tried top to bottom
  replies:
    - match: '\b(hello|hi)\b' # case-insensitive regexp
      reply: I am here.
  default: 'You said: "{input}".'
```

| Class | |
|---|---|
| `Persona.load(path)` | the YAML above; `#messages(facts = nil)` (system, plus the facts for one request, + examples), `#deflect(text)` (the reply of the first matching `deflect` rule, or nil: what a small model answers out of character however it is asked, so the code answers it), `#fallback(text)`, `#options` |
| `Client.new(url:, model: nil, api_key: nil, open_timeout: 2, read_timeout: 30)` | `#stream(messages, **options) { \|piece\| }` over `/v1/chat/completions` with `stream: true`; `#enabled?` is false for an empty URL |
| `Chat.new(persona:, client:, history: 6, key: :ai_history, filter: PLAIN_TEXT, options: {})` | `#reply(text, ctx, facts: nil, fallback: nil) { \|piece\| }` returns the reply and yields it as it streams. The history lives in `ctx[key]`, so it lasts for the call. `facts` is added to the system prompt for this one request (what the character should know right now, looked up for the question; not kept in the history); `fallback` replaces the persona's canned reply when the model is missing or fails. `filter` drops markdown marks and emoji. `options` override the persona's. |
| `Typewriter.new(io, prefix:, style:, width: nil)` | `#write(piece)`, `#finish(newlines: 2)`: word-wraps streamed text to the caller's terminal under the prefix |

- With an empty URL, or when the request fails before any text arrived, the
  reply is the persona's canned one. A reply cut off mid-way is kept.
- A small model copies its examples far better than it follows the system
  prompt, and a long history makes it repeat its own slips: prefer more
  examples and a short `history`.

---

## 18. Doors (`BBS::Door`)

A door is a program the caller steps into from the BBS, as in the doors of the
old boards: the BBS hands the telnet line over, the program talks to the
caller directly, and the line comes back when the program exits. The program
is a `BBS::FakeOS` definition (see the comment in `bbs/fake_os.rb`), a
`BBS::Flow`, or anything that responds to `call(session, context)`.

```ruby
APP = BBS::Application.define do
  door :sermo, Sermo::OS,                       label: '&SERMO'
  door :dice,  ->(session, ctx) { DiceGame.new(session).play }, label: '&Dice'

  menubar do
    menu '&Doors' do
      doors                                     # one item per declared door
    end
  end

  status_hint('F5', 'SERMO') { open_door(:sermo) }
end

BBS.config.flow = BBS::Flow.define do
  ask :username, prompt: 'Name'
  call do |ctx, runner|
    APP.run(session: runner.session, session_id: ctx[:session_id], context: ctx)
    nil
  end
end
```

- `open_door(:name)` ends the application with `:halt` and leaves the door in
  `context[:door]`. `APP.run` then runs the door and builds the application
  again; a plain `APP.build(...).run` would only end.
- `Door#run(session, context)` clears the screen and switches mouse reporting
  off for the program, and switches it back on (if `BBS.config.mouse`) when it
  returns. It can be used without an Application. An exception in the program
  is logged and the caller comes back to the board: a door's fault does not end
  the call (a dropped line still does).
- `on_door { |door, context| … }` in the Application DSL runs just before the
  line goes to a door: who is in which door, for a node list.
- The context hash is the same before, inside and after the door, so a door can
  keep its state for the rest of the call (the AI chat history, for example).
- A `BBS::Flow` door runs on a copy of the context instead, so its `ask` steps
  cannot overwrite the BBS's keys (`:username`, …). A flow has no exit command,
  so when it ends the door asks for ENTER before handing the line back. Give
  the flow its own `screens_dir` when it comes with screens.
- A FakeOS with a coloured screen sets `colors base:`: every reset returns to
  it and `cls` fills the screen with it, so a background survives the prompt,
  the caller's echo and new lines. Give each colour role the same background,
  since an SGR that starts with `0;` clears it.

### Telnet gateways (`BBS::Gateway`)

A door to another telnet board, the telnet gateway of the old BBSes: the line
goes on to that board as it is, and comes back when it hangs up. The other
board runs its own code on its own server; this one only carries the bytes.

```ruby
FEEDIA = BBS::Gateway.new(host: 'host.docker.internal', port: 2327, name: 'Feedia')
door :feedia, FEEDIA, label: '&Feedia'
```

- Towards the other board the gateway is the telnet client: it answers the
  negotiation (DO for ECHO and SGA, WILL for SGA, NAWS and TTYPE, a refusal for
  the rest), reports the caller's window size and passes later size changes
  on. Everything else goes through untouched both ways, mouse reports and
  PETSCII included.
- BINARY is not refused but passed on: when the other board asks for it (a
  `BBS::Xmodem` transfer) or leaves it, the gateway agrees and asks the
  caller's terminal the same, so ZMODEM and XMODEM downloads work through a
  gateway as they do on a direct call.
- A PETSCII line reports no window size, so a two-faced board on the other end
  (`BBS::Terminal`) takes the caller for a Commodore 64.
- When the other board hangs up, the caller is asked for a key and comes back;
  when it does not answer (5 s), the caller is told so and comes back. A caller
  who hangs up inside ends the call, and the other board's connection with it.
- `session.line` is the caller's socket, for a door like this one.

### File downloads (`BBS::Zmodem`)

The sending side of ZMODEM, so a caller's terminal can save a file from the
board: SyncTERM, NetRunner, Qodem, `rz` behind a plain telnet, or zmodem.js
in a web terminal (bbsweb). Run it inside `with_line`, so the screen is
clean and the application repaints afterwards:

```ruby
result = app.with_line do |session|
  session.write("  Sending README.TXT by ZMODEM; Esc gives up.\r\n")
  BBS::Zmodem.send_files(session, [['README.TXT', bytes, mtime]])
end
# => :ok, :cancelled, :timeout (no receiver answered) or :hangup
```

- Control characters go out ZDLE-escaped and 0xFF as a doubled telnet IAC,
  so it works without telnet BINARY mode; `telnet: false` for a plain pipe.
- It waits `wait:` seconds (30) for the receiver; Esc or Ctrl-C gives up
  meanwhile, and five CANs from the terminal cancel at any time.
- Data goes with CRC-32 when the receiver offers it, else CRC-16, in
  1 KB subpackets; a ZRPOS restarts from that position.
- The bytes go out with `session.write_raw`, past the PETSCII encoder.

### File downloads for a Commodore 64 (`BBS::Xmodem`)

The sending side of XMODEM, XMODEM-CRC and XMODEM-1K: the transfer the
terminals of a C64 know (CCGMS, Novaterm, UltimateTerm), and SyncTERM, Qodem
or `rx` too. XMODEM sends no file name, so tell the caller to name the file
and start the download in the terminal:

```ruby
result = app.with_line do |session|
  session.write("  Start an XMODEM download of ARIADNE.PRG now; Esc gives up.\r\n")
  BBS::Xmodem.send_file(session, bytes, one_k: true)
end
# => :ok, :cancelled, :timeout (no receiver started) or :hangup
```

- The receiver picks the check: a `C` gets CRC-16, a NAK the checksum. With
  `one_k: true` the blocks are 1024 bytes when the receiver asked for a CRC,
  else always 128.
- The last block is padded with SUB (0x1a), so the saved file can be up to a
  block longer. A C64 program loads all the same.
- It works on a PETSCII line: the bytes go out with `session.write_raw`, 0xFF
  as a doubled telnet IAC, and the line is asked into telnet BINARY mode for
  the transfer and back out after it (`telnet: false` for a plain pipe).
- It waits `wait:` seconds (60) for the receiver; Esc or Ctrl-C (RUN/STOP)
  gives up meanwhile, and two CANs from the terminal cancel at any time. A
  block goes again on a NAK or 20 s of silence, at most 10 times.

---

## 19. Telnet, sessions & input model

### `BBS::Session`

Wraps a TCP socket with Telnet negotiation and the input parser:

```ruby
session.session_id       # 16-hex SecureRandom id
session.term_cols        # NAWS column count (default 80)
session.term_rows        # NAWS row count    (default 24)
session.readline         # cooked line input (FlowRunner uses this)
session.readline(mask: '*') # same, echoing the mask instead of each character
session.naws_reported?   # true once the client sent its window size (NAWS)
session.readkey(timeout: 1.0)
session.write(bytes)
session.write_raw(bytes)  # as they are, not PETSCII-encoded (file transfers)
session.enable_mouse / disable_mouse
session.settle(timeout: 1.5) # wait for the telnet answers (NAWS), drop typeahead
session.petscii!         # from here on the line speaks PETSCII to a C64
session.petscii?
```

Telnet options negotiated on connect: `SGA` (suppress go-ahead), `ECHO`
(server-side echo), `NAWS` (terminal size, clamped to 20–500 × 8–200). A line
end goes before them: the UltimateTerm of the C64 Ultimate takes a line that
starts with a telnet command for ASCII with ANSI and translates every byte
from ASCII to PETSCII (CLR becomes nothing, letters swap case both ways), and
stays on PETSCII after any other first byte.
Mouse uses xterm 1000/1006 SGR mode; X10 reports are read too.

`readline` returns UTF-8 (invalid bytes dropped), takes at most 1024 bytes,
and ends on CR, LF, CR LF or CR NUL. `readkey` returns one `:enter` for
CR LF / CR NUL, a lone Esc after 0.15 s, and a UTF-8 character (`'á'`) as a
one-character String. `read_raw_byte(timeout)` is for binary protocols
(ZMODEM, XMODEM): one byte as an Integer, telnet commands taken out.

### PETSCII: a Commodore 64 on the line (`BBS::Petscii`)

`session.petscii!` turns the line into a C64's: 40×25 (`term_cols` /
`term_rows`), the lowercase character set (it sends `LOWERCASE`, `LOCK_CASE`
and `CLEAR`), and no mouse. From then on everything written goes through a
`BBS::Petscii::Encoder`, so the code above keeps writing UTF-8 with ANSI:

- letters swap case the PETSCII way; box drawing, blocks (`█` as a reversed
  space), `£ ← ↑ ✓` map to the C64's own glyphs; typography (`— … • ◄`) and
  accented letters to their nearest ASCII; anything else is `?`;
- ANSI colours become the C64's (`\e[1;33m` yellow, `\e[2;37m` grey, black is
  dark grey so a black-on-grey door stays readable; backgrounds are dropped),
  `\e[7m` / `\e[27m` reverse, `\e[2J` CLR, `\e[H` / `\e[r;cH` home and cursor
  moves, `\e[A`–`\e[D` the cursor keys; other sequences are dropped, even when a
  write cuts one in two;
- CR LF is one RETURN, and a lone CR goes back to the start of the line; the
  Encoder counts columns, so a line of exactly 40 characters, which the C64
  wraps by itself, gets no empty line after it;
- a `"` is followed by a second one, a cursor left, a space and another cursor
  left, so the C64 leaves the quote mode it entered and the colour and cursor
  codes after it keep working (except in the last two columns);
- PETSCII control codes can be written directly as the C0/C1 code points of a
  UTF-8 string: `"#{BBS::Petscii::YELLOW}READY."`. `LOCK_CASE` is ASCII's
  backspace, so send it raw.

`readkey` and `readline` read the C64's keys: letters in either case, RETURN
`:enter`, INST/DEL `:backspace` (and ASCII backspace and delete, which some
terminal programs send for it), the cursor keys, HOME, F1–F8, and RUN/STOP or
`←` as `:escape`; `readline` echoes in PETSCII. A Flow, a FakeOS or a door that
draws for 40 columns runs on a C64 unchanged; one drawn for 80 wraps.

`settle(timeout:)` waits for the client's answers to the negotiation and
drops whatever arrives meanwhile, so a board can guess the terminal before it
asks: a reported window wider than 40 columns is a modern terminal, 40 or no
report at all (a C64 behind a WiFi modem speaks plain TCP) most likely a C64.

### Input fields and the full-screen editor (`BBS::Field`, `BBS::Editor`)

Two inputs that edit text rather than take it typed again, on either face:
`BBS::Field` for a line (a name, a password, a title) and `BBS::Editor` for
text longer than that. Both keep the text and the cursor in a
`BBS::TextBuffer`, so the editing keys do the same in both: the cursor keys
move, typing inserts at the cursor, DEL (backspace) deletes before it, Delete
under it. Both draw through a `BBS::Cursor`, which moves only relative to
where it left the cursor and on a C64 goes down with RETURN, never with HOME
or cursor down, and neither writes into a C64's last column or row.

```ruby
session.write ' title> '
title = BBS::Field.new(session, text: post.title, width: 31, max: 80).run
pass  = BBS::Field.new(session, width: 20, mask: '*').run
body  = BBS::Editor.new(session, text: post.body, title: 'BODY').run
```

A field takes `width:` columns from the cursor, scrolls sideways when the text
is longer, and returns the text on RETURN or `nil` on RUN/STOP, `←` or Esc;
either way it writes a line end. HOME and END go to the ends of the text.
`BBS::Field.ask(session, prompt, text:, max:, mask:)` writes the prompt and
makes the field as wide as the rest of the prompt's last line. A Flow's `ask`
step types its answer in such a field on a C64.

The editor takes the whole screen (a title bar, the text wrapping at word
boundaries, a row of key hints). RUN/STOP, `←` or Esc ask on the bottom row:
`S` saves and `run` returns the text (lines joined by LF), `Q` returns `nil`,
any other key goes back to the text. F1 or Ctrl-S save at once where the
terminal program lets the key through (the Ultimate Term keeps F1 for its
help). With `single_line: true` it edits one paragraph and RETURN saves; with
`max:` the title bar counts the characters. HOME and END go to the ends of the
screen row, PgUp and PgDn a screenful. Both raise IOError when the caller
hangs up.

### A cursor menu for a line-by-line board (`BBS::Selector`)

A menu drawn at the cursor, for a board that talks line by line rather than
in windows, on a C64 as well as on a modern terminal. The items stand one
under the other (or side by side on one row with `across: true`), the lit one
a reversed bar: the cursor keys move it, RETURN takes it, and an item's own key
takes it at once, so callers who know the menu by its letters type as before.
Like `BBS::Field` it draws downwards from where the cursor is through a
`BBS::Cursor`, never with HOME, and leaves the cursor on the line under it.

```ruby
S = BBS::Selector
items = [S.heading('── latest ──'),
         S.item('Hello world', key: '1', value: post, about: post.summary),
         S.heading('── menu ──'),
         S.item('latest posts', key: 'l', value: :latest, about: 'every post, newest first'),
         S.item('log off',      key: 'q', value: :quit)]
choice = S.new(session, items, width: 38, hint: 'crsr: choose  return: open').run
case choice
when :latest then latest
when :quit, nil then return          # nil: RUN/STOP, ← or Esc (back:)
else show(choice)
end

post = S.list(session, posts, width: 38, height: 18, &:title)   # numbered
```

A heading labels the rows under it and is never lit. An item's `about` shows
on a row under the menu while it is lit; `hint` goes on a status row, with the
page (`2/3`) and the number being typed. `S.list` numbers the items: the
digits typed light the item of that number and RETURN takes it. With more
items than `height:` the menu turns into pages: the cursor runs on from one to
the next, left and right (`+` and `-`) turn them. `exits: { 'x' => :value }`
adds keys that return a value without an item. It raises IOError when the
caller hangs up.

With `columns: 2` (and a `height:`) the items run down the first column, then
down the next; CRSR left and right go to the item beside. An empty
`S.heading` keeps a place, so sections can stand level with each other, and
an item's `color:` gives its key and its bar a colour of their own:

```ruby
items = [S.heading("\e[1;32m\e[7m messages \e[27m"),
         S.item('message boards', key: 'm', value: :boards, color: "\e[1;32m"), S.heading,
         S.heading("\e[0;36m\e[7m content \e[27m"),
         S.item('file areas', key: 'f', value: :files, color: "\e[0;36m"),
         S.item('news', key: 'n', value: :news, color: "\e[0;36m")]
S.new(session, items, width: 39, columns: 2, height: 3).run
```

### The screen of a line-by-line C64 board (`BBS::Petscii::Screen`)

What every line-by-line C64 board writes for itself: the 40×25 screen of one
call and the ways such a board talks. The colours are two-letter ANSI
constants in `BBS::Petscii::Colors` (`WH YE CY LG GR DG LB BL GN RD PU OR`,
`RV`/`RO` reverse on/off), which the PETSCII line turns into the C64's own.

```ruby
module UI
  module Petscii
    BBS::Petscii::Colors.install(self)   # bare WH, LG … in every class nested here

    class Screen < BBS::Petscii::Screen  # or: Screen = BBS::Petscii::Screen
      def banner(text) = puts(" #{YE}#{text}#{LG}")   # the board's own methods
    end
  end
end

screen = UI::Petscii::Screen.new(runner.session)
screen.title('the shelves', 'q: back')          # CLR + reversed title bar
screen.say('A paragraph, wrapped to 38 columns.', GR)
screen.page('chapter 1', lines, numbers: true)  # 20 lines a page, RETURN for more
book = screen.pick('the shelves', books, &:title)   # numbered BBS::Selector.list
key  = screen.actions(%w[r read], %w[q back])       # a row of keys, cursor menu
name = screen.ask(' name> ', max: 20)               # BBS::Field
text = screen.edit('', title: 'TIP', single_line: true, max: 200)   # BBS::Editor
```

`Colors.install(mod)` is needed for a namespace module because Ruby looks a
bare constant up in the lexically enclosing modules, not in what they include;
a class can simply `include BBS::Petscii::Colors` (the Screen does, so its
subclasses have the names). On a C64 the screen makes titles, paragraphs and
list labels `plain` (`BBS::Petscii.plain`: typography and accents become
ASCII, so a line wraps where it is counted). `Screen.new(session, cols: 80,
rows: 24)` serves a modern terminal too: there it clears with ANSI and leaves
the text alone.

### Block-font logos, goodbyes, Discord (`BBS::BlockFont`, `BBS::Goodbye`, `BBS::DiscordWebhook`)

```ruby
F = BBS::BlockFont
F.half_blocks('WARP')                                   # 3 rows of ▀▄█ for a modern face
F.half_blocks('TTG BBS', colors: [YE, OR, RD])           # each row in its colour
F.petscii('SCRIPTORIUM', colors: [WH, WH, YE, YE, CY], glyphs: F::NARROW_I, indent: 2)
F.rows('TTG WIKI', glyphs: F::WIDE_W)                    # the pixel rows, # and .

BBS::Goodbye.modern(runner, title: 'Feedia', note: "The stories are their publishers'.")
BBS::Goodbye.petscii(screen, title: 'feedia', color: YE, note: "The stories are their publishers'.")
```

`BlockFont` is a 3×5 font (A–Z, 0–9, space and `. , ! ? - + : ' /`); `glyphs:`
lays other shapes over it. `Goodbye.modern` writes "Thanks for calling …",
the note, "More of us: teletypegames.org" and NO CARRIER; `Goodbye.petscii`
draws the reversed bar, the note (or what its block writes), then `+++`,
`ATH0` and NO CARRIER a moment apart.

`BBS::DiscordWebhook` is plain Ruby and loads alone (`require
'bbs/discord_webhook'`), for a board's domain layer:

```ruby
discord = BBS::DiscordWebhook.new(ENV['DISCORD_WEBHOOK'], embeds: false, label: 'commodex: Discord')
discord.post("🕹️ a tip from #{BBS::DiscordWebhook.escape(author)}")   # => Thread, or nil
```

It posts in a background thread with mentions off, cuts the content at `max:`
(1500), lets at most `relay_max:` posts (20) out in `relay_window:` seconds
(600; `relay_max: nil` for no limit), times out after `timeout:` (10 s), and
warns instead of raising. An empty URL turns it off (`enabled?`).

### Two faces on one port (`BBS::Terminal`)

A board with a modern face and a PETSCII face (a C64) asks the caller first, with the
guess above as the default:

```
TTG WIKI

1 - MODERN (ANSI/XTERM, 256 COLORS)
2 - COMMODORE 64 (PETSCII, 40 COLUMNS)

YOUR TERMINAL [1]:
```

```ruby
BBS.configure do |config|
  config.mouse            = true
  config.mouse_on_connect = false   # the mouse's escape sequence is garbage on a C64
  config.flow = BBS::Terminal.flow(title: 'TTG Wiki', modern: modern_flow, petscii: petscii_flow)
end
```

`Terminal.flow` asks, switches the line (`petscii!` on a C64, `enable_mouse`
on a modern terminal when `config.mouse` is on) and runs that face's Flow. The question is plain ASCII
capitals, which both machines print alike. A key (`1`/`M`, `2`/`C`/`P`) only
picks and RETURN takes it, so the RETURN of a line-mode telnet does not reach
the first screen; no answer in 60 s takes the pick or the guess.
`BBS::Terminal.choose(session, title:)` is the question alone: `:modern`,
`:petscii`, or nil when the line drops.

### `Session#readkey` return values

- Single-character `String` — printable input (`'a'`, `' '`, …).
- `Symbol` — one of:
  - Navigation: `:enter`, `:alt_enter`, `:tab`, `:shift_tab`, `:backspace`, `:escape`,
    with xterm modifiers as a prefix: `:shift_up`, `:ctrl_right`, `:ctrl_f5`, `:alt_home`, …
    (a window hands a modified arrow nothing takes to its widget as the plain key);
    `:up`, `:down`, `:left`, `:right`, `:home`, `:end`,
    `:page_up`, `:page_down`, `:insert`, `:delete`.
  - Function keys: `:f1`…`:f12`.
  - Control codes: `:ctrl_a`…`:ctrl_z` (raw 1–26 minus a few that map to
    other things — Enter, Tab, Backspace, Esc, Ctrl-C).
  - Alt-modified printables: `:alt_a`…`:alt_z`, `:alt_0`, …
    (any printable preceded by ESC).
  - `:interrupt` — Ctrl-C.
  - `:idle` — the supplied `timeout` expired.
- `BBS::Telnet::MouseEvent` — when `BBS.config.mouse = true`. Fields:
  - `kind`: `:press`, `:release`, `:move`, `:wheel`.
  - `button`: `:left`, `:middle`, `:right`, `:up`, `:down` (wheel), `:none`.
  - `x`, `y`: terminal-relative, 1-based.
  - `mods`: array of `:shift`, `:ctrl`, `:meta`.

### `BBS::Event`

Application/Window/Widget `handle_event` receives a normalised `BBS::Event`:

```ruby
event.kind       # :key, :mouse, :idle, :resize, :tick
event.key?       # kind == :key
event.mouse?     # kind == :mouse
event.key        # the Symbol/String key
event.mouse      # the Telnet::MouseEvent
event.x, event.y # mouse position
event.alt?       # key.to_s.start_with?('alt_')
event.alt_char   # 'x' from :alt_x
event.char?      # key is a 1-char String
```

Return `:halt` to end the application, `:handled` to stop propagation,
`nil`/`false` to keep dispatching.

---

## 20. Source layout

| File | Responsibility |
|---|---|
| `lib/bbs.rb` | Public surface: `BBS.configure`, `BBS.config`, `BBS.start`. |
| `bbs/server.rb` | TCP accept loop, one thread per client, on-session-end hook. |
| `bbs/session.rb` | Telnet negotiation, mouse enable/disable, idle timer. |
| `bbs/telnet.rb` | Telnet protocol, full key parsing, xterm SGR mouse, PETSCII mode. |
| `bbs/petscii.rb` | PETSCII: the C64's colours and controls, the UTF-8/ANSI → PETSCII encoder, the C64's keys. |
| `bbs/petscii/colors.rb`, `bbs/petscii/screen.rb` | The ANSI colour constants and the 40×25 screen of a line-by-line C64 board. |
| `bbs/block_font.rb` | A 3×5 block font for logos: half blocks (modern) and reversed spaces (C64). |
| `bbs/goodbye.rb` | The NO CARRIER screen of a call, modern and C64. |
| `bbs/discord_webhook.rb` | Discord webhook posts, standalone: background thread, mentions off, relay limit. |
| `bbs/terminal.rb` | The terminal question of a two-faced board: modern (ANSI) or C64 (PETSCII). |
| `bbs/config.rb` | `BBS::Config` value object. |
| `bbs/flow.rb`, `bbs/flow_runner.rb` | Flow DSL + interpreter. |
| `bbs/tui.rb`, `bbs/tui_runner.rb` | Page-router with frame-buffer rendering and the drawing-primitive context. |
| `bbs/frame_buffer.rb` | Double-buffer, delta diff, drawing helpers, ANSI string utilities. |
| `bbs/application.rb` | Widget event loop, window stack, ticking, builder DSL. |
| `bbs/widget.rb`, `bbs/container.rb` | Widget tree base. |
| `bbs/widgets.rb` | Built-in widgets (Label, Button, TextInput, TextArea, Checkbox, ListBox, ScrollView, ProgressBar, Spinner, HBox, VBox, Panel). |
| `bbs/widgets/ansi_art.rb` | CP437 / ANSI art widget with SAUCE stripping. |
| `bbs/window.rb`, `bbs/window_spec.rb` | `Window` + declarative window DSL. |
| `bbs/windows/info.rb` | Centered info / message / kv / scroll dialog. |
| `bbs/windows/form.rb` | Multi-field form with status line. |
| `bbs/windows/master_detail.rb` | Two-pane list / detail browser. |
| `bbs/windows/stream.rb` | Live log / chat window with input + polling. |
| `bbs/windows/button_bar.rb` | Bottom-row button layout helper. |
| `bbs/menu.rb`, `bbs/statusbar.rb`, `bbs/dialogs.rb` | Chrome + ad-hoc dialogs. |
| `bbs/focus_manager.rb` | Tab/Shift-Tab focus traversal. |
| `bbs/theme.rb` | Style palette (synchronet, nortoncommander, dosnavigator, neumanntronics, mono). |
| `bbs/markdown.rb` | Markdown → ANSI line array renderer. |
| `bbs/event.rb` | Unified key + mouse event objects. |
| `bbs/store.rb` | Thread-safe cached CSV upsert. |
| `bbs/fake_os.rb` | Character-mode OS simulator: boot script + command shell. |
| `bbs/door.rb` | Doors: hand the line to a program and take it back. |
| `bbs/gateway.rb` | Telnet gateway doors: the line handed on to another board. |
| `bbs/zmodem.rb` | ZMODEM send: file downloads to the caller's terminal. |
| `bbs/xmodem.rb` | XMODEM / XMODEM-CRC / XMODEM-1K send: file downloads for a Commodore 64. |
| `bbs/ai.rb` | AI characters: persona file, OpenAI-compatible streaming client, chat with memory and fallback, typewriter output. |
| `bbs/banner.rb`, `bbs/renderer.rb` | FIGlet + ERB. |
| `bbs/color.rb` | Simple ANSI colour helper. |
