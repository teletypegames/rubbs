# rubbs

A Ruby gem for building telnet BBS servers with a declarative conversation flow DSL.

## Installation

```ruby
# Gemfile
gem 'bbs', git: 'https://git.teletype.hu/tools/rubbs.git'
```

## Quick start

```ruby
require 'bbs'

sessions = BBS::Store.new(path: 'data/sessions.csv', headers: %w[session_id timestamp name])

BBS.configure do |c|
  c.screens_dir = 'screens'
  c.stores      = [sessions]
  c.flow        = BBS::Flow.define do
    screen :welcome
    ask :name, prompt: "What is your name?"
    say "Hello, %{name}!", style: :success
    persist :name, store: sessions
  end
end

BBS::Server.start
```

Connect with `telnet localhost 2323`. The port defaults to `2323` and can be overridden with the `BBS_PORT` environment variable.

## Configuration

`BBS.configure` yields a `BBS::Config` object:

| Option | Default | Description |
|---|---|---|
| `screens_dir` | `"screens"` | Directory containing ERB screen files |
| `stores` | `[]` | List of `BBS::Store` instances |
| `flow` | — | A `BBS::Flow` object (required) |
| `port` | `ENV["BBS_PORT"] \|\| 2323` | TCP port to listen on |

## Flow DSL

The entire dialogue is defined as a declarative `BBS::Flow.define` block.

### Primitives

| Primitive | Description |
|---|---|
| `screen :name, **vars` | Render an ERB screen from `screens/`; vars override/extend the context |
| `banner "text", style:` | Print a box-drawing ASCII banner |
| `big_banner "text", style:, font:` | Print a large FIGlet ASCII-art banner (default font: `slant`) |
| `say "text", style:` | Print a single styled line |
| `ask :field, prompt:, transform:, validate:` | Read input and store it in the session context |
| `set :field, value` | Set a context variable directly from code |
| `persist :field, …, store:` | Write named context fields to a `BBS::Store` |
| `pause "message", seconds:` | Display a message and sleep |
| `gate denied: "…" { \|ctx\| bool }` | Halt the flow unless the block returns true |
| `confirm "message", denied: "…"` | Yes/no gate — halts on no |
| `confirm "message", denied: "…" { }` | Yes/no branch — runs the block on yes, skips on no |
| `menu "prompt", loop: bool { }` | Numbered option menu; loops back after each selection when `loop: true` |
| `exit_menu` | Break out of the enclosing `menu` loop and continue the parent flow |

### `ask` options

| Option | Description |
|---|---|
| `prompt:` | The string printed before the cursor |
| `transform:` | A proc applied to the raw input before storing (e.g. `transform: :upcase.to_proc`) |
| `validate:` | A proc that returns `true` if the value is acceptable; the question is repeated on failure |

### Banner styles

`:success`, `:info`, `:error`, `:warning`, `:muted` — each maps to an ANSI colour.

### Menu example

```ruby
menu ">", loop: true do
  option "Leave feedback" do
    ask :feedback, prompt: "Feedback"
    persist :feedback, store: sessions
    say "Recorded. Thank you.", style: :success
  end

  option "Exit" do
    exit_menu
  end
end

say "Goodbye!", style: :muted
```

## Screens

ERB files in `screens/` have access to ANSI colour helpers and a `banner` helper. Context variables set by `ask`, `set`, or passed explicitly to `screen` are available as `@field`.

```erb
<%= banner("MISSION COMPLETE") %>

  <%= white %>Congratulations!<%= reset %> You are <%= yellow %><%= @name %><%= reset %>.
```

### ANSI helpers

`black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, `reset`, `bold`, `dim`

## Stores

Each `persist` step writes to a `BBS::Store` (a thread-safe, append-and-upsert CSV file). `session_id` and `timestamp` are always written automatically.

```ruby
identities = BBS::Store.new(path: 'data/identities.csv', headers: %w[session_id timestamp name code])
signups    = BBS::Store.new(path: 'data/signups.csv',    headers: %w[session_id timestamp email])

persist :name, :code, store: identities
persist :email,       store: signups
```

Rows are keyed by `session_id`: the first `persist` for a session creates the row; subsequent ones update it in place.

## Architecture

| File | Responsibility |
|---|---|
| `bbs/server.rb` | TCP accept loop, spawns one thread per client |
| `bbs/session.rb` | Negotiates telnet options, runs the flow |
| `bbs/telnet.rb` | Telnet protocol (IAC handling, echo control, readline) |
| `bbs/flow.rb` | Flow DSL builder |
| `bbs/flow_runner.rb` | Executes a Flow step by step against a session context |
| `bbs/config.rb` | Configuration object |
| `bbs/banner.rb` | Box-drawing and FIGlet banner renderer |
| `bbs/renderer.rb` | ERB screen loader with ANSI colour helpers |
| `bbs/store.rb` | Thread-safe CSV persistence |
