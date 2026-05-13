# rubbs

A Ruby gem for building telnet BBS servers.  Three interaction layers, from
simplest to richest:

| Layer | What it is | When to use |
|---|---|---|
| `BBS::Flow` | Line-oriented declarative dialogue DSL (ask / say / menu / persist) | Login, registration, simple wizards |
| `BBS::TUI` | Page-router with frame-buffer delta rendering | Single-purpose full-screen UIs |
| `BBS::Application` | Full widget framework: Menubar, Window, Button, TextInput, ListBox, … | Multi-window Synchronet-style BBSes |

A single session can switch between layers — typically `Flow` for login then
`Application` for the main shell.

## Installation

```ruby
# Gemfile
gem 'bbs', git: 'https://git.teletype.hu/tools/rubbs.git'
```

## Quick start — Flow + Application

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

  status_hint('F1', 'Help') { BBS::Dialogs.message(self, 'No help yet.') }
  status_hint('F10', 'Menu') { menubar.open(0) }
end

BBS.configure do |c|
  c.mouse        = true
  c.idle_seconds = 600
  c.flow = BBS::Flow.define do
    big_banner 'MY BBS', style: :success
    ask :username, prompt: 'Name'
    app MAIN
    say 'Goodbye!'
  end
end

BBS.start
```

Connect with `telnet localhost 2323`.

## Configuration

`BBS.configure` yields a `BBS::Config`:

| Option | Default | Description |
|---|---|---|
| `flow` | — | A `BBS::Flow` object (required) |
| `port` | `ENV["BBS_PORT"] \|\| 2323` | TCP port |
| `mouse` | `false` | Enable xterm SGR mouse reporting |
| `idle_seconds` | `nil` | Disconnect after N idle seconds (nil = never) |
| `theme` | — | Default theme for Applications (overridable per app) |
| `screens_dir` | `nil` | Directory for ERB screens used by `BBS::Flow#screen` |
| `on_session_end` | `nil` | Lambda called when a session ends |

## The Application layer

`BBS::Application` is a widget event loop with:

- a root container drawn behind windows;
- an optional `Menubar` with Alt-letter pulldown menus and F10 access;
- an optional `Statusbar` with clickable hotkey hints;
- a stack of modal `Window`s (the top one receives input first);
- xterm SGR mouse events delivered to widgets;
- a 1 Hz internal tick for chat polling, clocks, etc.

### Built-in widgets (`BBS::Widgets`)

| Widget | Purpose |
|---|---|
| `Label` | Static text, optionally aligned, themed via `style_key` |
| `Button` | `&Save`-style hotkey, fires `on_click(self)`; mouse-clickable |
| `TextInput` | Single-line input with cursor, scroll, `on_submit`/`on_change` |
| `TextArea` | Multi-line editor with arrow-key navigation |
| `Checkbox` | Toggle with `on_change(checked, self)` |
| `ListBox` | Scrolling list with mouse + keyboard, wheel scrolling |
| `ScrollView` | Read-only scrolling text view, with scrollbar |
| `ProgressBar`, `Spinner` | Progress feedback |
| `Panel`, `HBox`, `VBox` | Containers / layout |
| `Window` | Top-level modal container with title bar, close gadget, shadow |
| `AnsiArt` | CP437 / ANSI art renderer with SAUCE stripping (`AnsiArt.from_file`, `AnsiArt.random(dir)`) |

### Built-in dialogs (`BBS::Dialogs`)

```ruby
BBS::Dialogs.message(app, "Saved!", title: ' Done ')
BBS::Dialogs.confirm(app, "Delete?", on_yes: -> { ... })
BBS::Dialogs.input(app, prompt: 'Name?', on_submit: ->(value) { ... })
```

### Pre-built window types (`BBS::Windows`)

High-level modal windows you can open imperatively with `.open(app, …)` or
declaratively via the window DSL (see below).

| Window | Purpose |
|---|---|
| `Info` | Centered dialog for messages, splash screens, key/value displays, optional scroll mode |
| `Form` | Labeled input rows + textarea + checkbox + status line for inline validation |
| `MasterDetail` | Two-pane browser: ListBox on the left, ScrollView of details on the right |
| `Stream` | Live history view + single-line input + idle-tick polling (chat, logs) |
| `ButtonBar` | Helper that lays out a row of buttons at the bottom of any window |

Example — opening directly:

```ruby
BBS::Windows::Info.open(app,
  title: ' Welcome ',
  width: 70,
  body: [
    { text: 'rubbs', style: :accent },
    :spacer, :rule,
    { kv: [['Online', '5'], ['Ruby', RUBY_VERSION]] },
  ])

BBS::Windows::Form.open(app,
  title: ' Profile ',
  fields: [
    { key: :sig,  label: 'Signature', value: '...' },
    { key: :bio,  label: 'Bio',       type: :textarea, rows: 6 },
    { key: :nsfw, label: 'Show NSFW', type: :checkbox, value: false },
  ],
  on_submit: ->(values, form) {
    return (form.error('Bio required.'); :keep) if values[:bio].empty?
    save(values); :close
  })

BBS::Windows::Stream.open(app,
  title: ' Live Chat ',
  initial_lines: chat.history,
  placeholder: 'Type and press Enter…',
  on_submit: ->(text, _app) { chat.broadcast(username, text) },
  on_poll:   ->(_app)       { chat.drain(session_id) })
```

### Window DSL — declarative windows

Register windows by name inside `Application.define`, then open them by symbol.
Block callbacks receive a `ctx` hash combining the app's services, app context,
and any extras passed to `open_window`.

```ruby
MAIN = BBS::Application.define do
  services chat: ChatService.new, boards: BoardService.new

  window :compose, type: :form do |w|
    w.title { |ctx| " Post to #{ctx[:board].title} " }
    w.width 70
    w.field :body, type: :textarea, max_length: 1000
    w.on_submit do |values, form, ctx|
      case ctx[:boards].post(ctx[:board].id, ctx[:username], values[:body])
      when :empty then form.error('Message cannot be empty.'); :keep
      else :close
      end
    end
  end

  window :games, type: :master_detail do |w|
    w.title         ' Game Catalog '
    w.items         { |ctx| ctx[:games].all }
    w.item_label    { |g, _ctx| g.title }
    w.render_detail { |g, width, _ctx| GameCard.lines(g, width) }
    w.action(label: '&New') { |_win, ctx| ctx[:app].open_window(:new_game) }
  end
end

# Later, inside a menu handler:
app.open_window(:compose, board: current_board)
```

`window :name, type:` supports `:info`, `:form`, `:master_detail`, `:stream`.
Inside the block, scalar attrs (`title`, `width`, …) and block attrs (`body`,
`items`, `on_submit`, …) accept either a value or a `{ |ctx, …| … }` block.
Use `w.field` for form fields, `w.action` for master-detail action buttons,
and `w.button` for info-window buttons.

### Menubar DSL

```ruby
menubar do
  menu '&File' do
    item '&Open', shortcut: 'Ctrl-O' do … end
    separator
    item 'E&xit' do :halt end
  end
end
```

The block runs in the Application's context (so you can call `open_window`,
`close_window`, `cols`, `rows`, etc.). Return `:halt` from any handler to end
the session.

### Theming

Built-in palettes: `synchronet` (default), `nortoncommander`, `dosnavigator`,
`neumanntronics`, `mono`. Apply one and/or override individual style keys with
the `theme` DSL block:

```ruby
MAIN = BBS::Application.define do
  theme :nortoncommander do
    window_border "\e[1;36;44m"
    accent        "\e[1;33;44m"
  end
end
```

Pass a `BBS::Theme` instance directly to use it as-is, or build one from
scratch with `BBS::Theme.new(:my_theme, { window_border: "\e[1;36m", … })`.

### Per-window ticks

`BBS::Application` fires a ~1 Hz tick when idle and calls `tick(app)` on each
open window. `BBS::Windows::Stream` uses this for polling. Override `tick` in
your own `Window` subclasses to refresh clocks, drain queues, etc.

### Markdown → ANSI

`BBS::Markdown.to_lines(text, width:, theme:)` returns an Array of ANSI-styled
strings suitable for feeding to `BBS::Widgets::ScrollView` or `Info`'s scroll
mode. Supports headings, bold/italic/code spans, links, quotes, bullet lists,
code blocks, and horizontal rules.

## The Flow layer

The DSL for line-based dialogue. Available steps:

| Step | Purpose |
|---|---|
| `screen :name` | Render an ERB screen from `screens/` |
| `banner`, `big_banner` | Box-drawing / FIGlet ASCII art header |
| `say`, `text`, `section`, `line`, `body` | Text output |
| `ask :field`, `set :field, value`, `persist :field, store:` | Input + persistence |
| `pause`, `wait_enter`, `gate`, `confirm` | Control flow |
| `menu`, `exit_menu` | Numbered option menus |
| `fetch`, `pick` | Data fetch + list selection |
| `rows`, `table` | Formatted output |
| `call { \|ctx, runner\| … }` | Arbitrary code; return `:halt` to end |
| `tui DEFINITION` | Hand off to a `BBS::TUI` page router |
| `app DEFINITION` | Hand off to a `BBS::Application` widget app |

## Input model

`Session#readkey(timeout:)` returns one of:

- a single-character `String` (printable input)
- a `Symbol`: `:enter`, `:tab`, `:shift_tab`, `:backspace`, `:escape`,
  `:up`, `:down`, `:left`, `:right`, `:home`, `:end`,
  `:page_up`, `:page_down`, `:insert`, `:delete`,
  `:f1` … `:f12`, `:ctrl_a` … `:ctrl_z`,
  `:alt_a` … (any printable character preceded by ESC),
  `:interrupt`, `:idle`
- a `BBS::Telnet::MouseEvent` with `kind`, `button`, `x`, `y`, `mods` —
  delivered when `BBS.config.mouse = true`

## Stores

`BBS::Store` is a thread-safe upsert-by-`session_id` CSV file with an
in-memory cache; appends are O(1), full rewrites only on update.

## Architecture

| File | Responsibility |
|---|---|
| `bbs/server.rb` | TCP accept loop, one thread per client |
| `bbs/session.rb` | Telnet negotiation, mouse enable/disable, idle timer |
| `bbs/telnet.rb` | Telnet protocol, full key parsing, xterm SGR mouse |
| `bbs/config.rb` | `BBS::Config` value object |
| `bbs/flow.rb`, `bbs/flow_runner.rb` | Flow DSL + interpreter |
| `bbs/tui.rb`, `bbs/tui_runner.rb` | Page-router with frame-buffer rendering |
| `bbs/frame_buffer.rb` | Double-buffer, delta diff, drawing helpers |
| `bbs/application.rb` | Widget event loop, window stack, ticking, DSL builder |
| `bbs/widget.rb`, `bbs/container.rb` | Widget tree base |
| `bbs/widgets.rb` | Built-in widgets |
| `bbs/widgets/ansi_art.rb` | CP437/ANSI art widget |
| `bbs/window.rb`, `bbs/menu.rb`, `bbs/statusbar.rb`, `bbs/dialogs.rb` | Chrome |
| `bbs/window_spec.rb` | Declarative window DSL (`WindowSpec`) |
| `bbs/windows/info.rb` | Centered info / message / kv dialog |
| `bbs/windows/form.rb` | Multi-field form with status line |
| `bbs/windows/master_detail.rb` | Two-pane list / detail browser |
| `bbs/windows/stream.rb` | Live log / chat window with input + polling |
| `bbs/windows/button_bar.rb` | Bottom-row button layout helper |
| `bbs/focus_manager.rb` | Tab/Shift-Tab focus traversal |
| `bbs/theme.rb` | Style palette (synchronet, nortoncommander, dosnavigator, neumanntronics, mono) |
| `bbs/markdown.rb` | Markdown → ANSI line array renderer |
| `bbs/event.rb` | Unified key + mouse event objects |
| `bbs/store.rb` | Thread-safe cached CSV upsert |
| `bbs/banner.rb`, `bbs/renderer.rb` | FIGlet + ERB |
| `bbs/color.rb` | Simple ANSI colour helper |
