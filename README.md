# rubbs

A Ruby gem for building telnet BBS servers. A board says what it is (its
name, its domain, its commands, menus, windows and screens) and rubbs does
the wiring: the telnet line, the terminal question, a windowed face for a
modern terminal, a line-by-line face for a Commodore 64, the goodbye.

```ruby
require 'bbs'

Bulletin = Struct.new(:text)

class MyBBS
  include BBS::Domain

  setting :motd, 'Welcome!'                       # MY_BBS_MOTD, else 'Welcome!'
  service(:bulletin) { Bulletin.new(motd) }       # a reader of the faces
end

APP = BBS::Application.define do
  command(:bulletin, 'Bulletin', key: 'F2') { message(bulletin.text, title: 'Bulletin') }
  menu 'Board', :bulletin, :separator, :log_off
end

BBS.board 'My BBS', MyBBS do
  modern APP
  goodbye 'Come back soon.'
end
```

Connect with `telnet localhost 2323`.

Upgrading from 1.x: see [UPGRADING.md](UPGRADING.md). A complete small board to start from:
[examples/sample-bbs](examples/sample-bbs) (a guestbook, both faces, tests and `rake bbs:check`).

---

## Table of contents

1. [Concepts](#1-concepts)
2. [Installation & quick start](#2-installation--quick-start)
3. [The board: `BBS.board` and `BBS::Domain`](#3-the-board-bbsboard-and-bbsdomain)
4. [Server lifecycle](#4-server-lifecycle)
5. [The Flow layer](#5-the-flow-layer)
6. [The Application layer](#6-the-application-layer)
7. [The line-by-line face: `BBS::Petscii::Face`](#7-the-line-by-line-face-bbspetsciiface)
8. [Full-screen pages: `BBS::Pages` and `BBS::Page`](#8-full-screen-pages-bbspages-and-bbspage)
9. [Widgets](#9-widgets)
10. [Windows](#10-windows)
11. [Declared windows (`window :name, :type`) and `BBS::Windows`](#11-declared-windows-window-name-type-and-bbswindows)
12. [Dialogs](#12-dialogs)
13. [Menubar, Statusbar, Focus](#13-menubar-statusbar-focus)
14. [Theming, the palette and `BBS::Style`](#14-theming-the-palette-and-bbsstyle)
15. [FrameBuffer & ANSI text](#15-framebuffer--ansi-text)
16. [Markdown renderer](#16-markdown-renderer)
17. [Banner & ERB screens](#17-banner--erb-screens)
18. [Persistence and shared blocks (`Model`, `Database`, `Store`, `Snapshot`, `HTTP`, `Cache`, `RateLimit`, `Text`, `Nodes`)](#18-persistence-and-shared-blocks-model-database-store-snapshot-http-cache-ratelimit-text-nodes) — and QR codes (`BBS::QR`)
19. [AI characters (`BBS::AI`)](#19-ai-characters-bbsai)
20. [Doors (`BBS::Door`)](#20-doors-bbsdoor) — telnet gateways (`BBS::Gateway`) and file downloads (`BBS::Zmodem`, `BBS::Xmodem`, `BBS::Transfer`)
21. [Telnet, sessions & input model](#21-telnet-sessions--input-model) — and testing a board (`bbs/test`)
22. [Source layout](#22-source-layout)

---

## 1. Concepts

A board is declared, not wired. `BBS.board` names it, gives it its domain
object and its faces, and starts the server; each face is declared in the
layer made for it.

| Layer | What it is | When to use |
|---|---|---|
| `BBS.board` | The board: its title, its domain class, its faces, its goodbye | Once, in the board's `bbs.rb` |
| `BBS::Domain` | The board's domain object: settings from the environment, files, services, background work | What the board knows and does, whatever the terminal |
| `BBS::Application` | The windowed face: menubar, statusbar, desktop, windows, declared with `Application.define` | A modern terminal (ANSI, xterm colours, mouse) |
| `BBS::Petscii::Face` | The line-by-line face: a title bar, a masthead, a main menu, the screen's helpers | A Commodore 64 (40×25 PETSCII), or a modern terminal line by line |
| `BBS::Pages` | A full-screen page app for both faces: a stack of `BBS::Page`, repainted by what changed | A picture-led or full-screen face on either terminal |
| `BBS::Flow` | Line-oriented steps (ask / say / menu / persist / call) | What comes before a face: a banner, a sign-up |

Building blocks sit beside them:

| Block | What it is | When to use |
|---|---|---|
| `BBS::FakeOS` | A character-mode OS simulator: boot script + command shell | A simulated machine the caller types into |
| `BBS::Door` | Hands the line from a face to a program and back | Games, simulated machines, anything full-line inside a board |
| `BBS::AI` | A persona-driven chat with a small model, streamed to the terminal | A character the caller can talk to, e.g. in a FakeOS `on_unknown` |
| `BBS::Petscii` | A Commodore 64 on the line: PETSCII out, the C64's keys in (`session.petscii!`) | A PETSCII face of a board, on the same flows and doors |
| `BBS::Terminal` | The first question of a two-faced board: modern (ANSI/xterm) or PETSCII (a C64) | Built by `BBS.board` when a board has both faces |
| `BBS::Preset` | What a family of boards shares: splash, goodbye address and QR code, User-Agent | One per family of boards (`TTG::PRESET` in `ttg-common`) |

The server boots a telnet TCP listener and hands each connection a
`Session`, which runs the root `Flow` that `BBS.board` built: the terminal
question (with two faces), the face, then the goodbye.

```
TCPServer → Session → FlowRunner ─┬→ Terminal question (two faces) → splash
                                  ├→ Application#run ⇄ Door#run (FakeOS, …)
                                  ├→ Petscii::Face#run (or a BBS::Pages runner)
                                  └→ Goodbye.show
```

---

## 2. Installation & quick start

### Gemfile

```ruby
gem 'bbs', git: 'https://git.teletypegames.org/engines/rubbs.git'
```

### A board with two faces

The whole of such a board, with its domain layers, a form, tests and the
Rakefile, is [examples/sample-bbs](examples/sample-bbs).

The board's domain, a small windowed face, a small line-by-line face, and
the board itself:

```ruby
require 'bbs'

class NewsBBS
  include BBS::Domain

  path    :db, 'data/news.sqlite3'            # NEWS_BBS_DB
  service(:news) { NewsService.new(database(db, *NewsService::MIGRATIONS)) }
end

MODERN = BBS::Application.define do
  theme :synchronet

  command(:latest, 'Latest news', key: 'F2', hint: 'News') { show(:latest) }
  menu 'News', :latest, :separator, :log_off
  help about: 'News BBS, a rubbs board.'
  status { "#{news.size} stories" }

  desktop do
    art  BBS::BlockFont.half_blocks('NEWS'), top: 2
    line(bottom: 1) { "#{news.size} stories today" }
    on_show { show(:latest) }
  end

  window :latest, :master_detail do
    title  'Latest news'
    items  { news.latest }
    label  :title
    detail { |story, width| markdown(story.body, width) }
  end
end

class C64 < BBS::Petscii::Face
  title('NEWS BBS') { "#{news.size} stories" }

  masthead do
    logo 'NEWS', colors: [YE, YE, OR, OR, RD]
    line 'the news on your commodore', color: WH
  end

  main_menu do
    item('l', 'latest news', 'newest first') { each_pick('LATEST', news.latest, label: :title) { |s| read(s) } }
    log_off
  end

  private

  def read(story) = page(story.title.upcase, markdown(story.body))
end

BBS.board 'News BBS', NewsBBS do
  modern  MODERN
  petscii C64
  goodbye 'Stories from our newsroom.'
end
```

`BBS.board` reads the settings from the environment (`NEWS_BBS_…`), makes
the domain object, asks the caller's terminal, runs the face, says goodbye
and serves callers until the process ends.

### Something before the face

A face given as a block is a Flow: the steps before the face, and the face
as its last step.

```ruby
BBS.board 'TTG Wiki', WikiBBS do
  modern { big_banner 'TTG WIKI'; app MODERN }
  petscii C64
end
```

---

## 3. The board: `BBS.board` and `BBS::Domain`

### `BBS.board`

```ruby
BBS.board 'Feedia BBS', FeediaBBS do
  preset  TTG::PRESET                    # splash, goodbye address + QR, User-Agent
  modern  UI::Modern::APP                # an Application definition …
  petscii UI::Petscii                    # … or a BBS::Petscii::Face subclass, a Flow, or a block
  goodbye "The stories are their publishers'."
  idle 900                               # default 600
  mouse false                            # default true on the modern face
  on_start { |bbs| Web::Api.new(bbs).start }                      # once at boot
  on_session_end { |session, bbs| bbs.end_call(session.session_id) }
end
```

`BBS.board(title, domain = nil, slug: nil) { … }` evaluates the block in a
`BBS::BoardDefinition`, applies it and starts the server; it does not
return while the server runs.

| Declaration | Effect |
|---|---|
| `preset(preset)` | The board's `BBS::Preset` (below). Default `BBS::Preset::NONE`. |
| `modern(face, goodbye: true)` / `modern { \|bbs\| … }` | The face of a modern terminal. |
| `petscii(face, goodbye: true)` / `petscii { \|bbs\| … }` | The face of a Commodore 64. |
| `goodbye(note, clear:, color:, bar:, art:, greeting:)` / `goodbye { \|context, session\| … }` | The board's own line on the goodbye screen (its sources, its licence), or a block for a line of each call; the options of `BBS::Goodbye.show` (modern: `clear`; C64: the bar's `color` and text, `art` lines under it). `goodbye false` leaves the goodbye to the faces. |
| `idle(seconds)` / `idle { \|bbs\| … }` | Seconds before a quiet caller is dropped (default 600); a block gets the domain object. |
| `mouse(on)` | Whether the modern face uses the mouse (default `true`). |
| `on_start { \|board\| … }` | Run once at boot with the domain object, after its `start`: an HTTP API beside the telnet port, say. |
| `on_session_end { \|session, board\| … }` | Run after each call, also when it ended with an error. |

A face is one of:

- a `BBS::Application` definition (`Application.define`): the windowed face;
- a `BBS::Petscii::Face` subclass, or any class made with
  `new(session, context, board)` that has a `run`: a line-by-line face, a
  `BBS::Pages` runner;
- a `BBS::Flow`: run as it is;
- a block: a Flow defined by it and given the domain object, for what comes
  before the face (`modern { |bbs| big_banner 'TTG WIKI'; app UI::Modern::APP }`).

A face's flow runs in a runner of its own, so a refusal in it (a `gate`)
still reaches the goodbye.

`goodbye: false` on a face says that face writes its own goodbye; the
others still get `BBS::Goodbye.show` after them. With one face only
(`modern` without `petscii`) there is no terminal question.

What `BBS.board` does with the declaration:

- From the title come the log tag and the environment prefix:
  `Feedia BBS` → `feedia-bbs` (`BBS.config.log_tag`) and `FEEDIA_BBS_`
  (`BBS.config.env_prefix`). When the technical name differs, say it:
  `BBS.board 'WarpEngine BBS', WarpEngineBBS, slug: 'warp-engine-bbs'`.
- The domain class is made once (`BBS.config.board`) and its `start` called
  when it has one; its `services` are what the faces get.
- `BBS.config.title`, `preset`, `idle_seconds`, `mouse` and
  `mouse_on_connect` (off when the board has a C64 face: the mouse's escape
  sequence is garbage on a C64) are set from it.
- The root flow is built: with two faces `BBS::Terminal.flow` (the
  terminal question and the preset's splash) over the two faces' flows;
  each face's flow is the face, then the `goodbye` step.

`BBS.config` and `BBS.configure` stay the low-level settings underneath (see
[§4](#4-server-lifecycle)); a board declared with `BBS.board` does not need
them.

### `BBS::Domain`

The board's domain object, declared: its settings from the environment,
its files, its services and its background work.

```ruby
class FeediaBBS
  include BBS::Domain

  setting :refresh, 3600                    # FEEDIA_BBS_REFRESH, cast to the default's type
  setting :languages, %w[en hu]             # an Array default splits on commas
  path    :db, 'data/feedia.sqlite3'        # FEEDIA_BBS_DB, expanded against the board's root

  service(:feeds) { FeedService.new(FeedRepository.new(database(db, *FeedRepository::MIGRATIONS))) }
  service(:inbox) { InboxService.new(feeds) }

  background('feed refresh', every: -> { refresh }) { feeds.refresh }
end
```

| Class macro | Effect |
|---|---|
| `setting(name, default = nil, env: nil, blank: false)` | An instance method reading `ENV["#{env_prefix}#{NAME}"]` (or the `env:` name after the prefix), else `default`. The value takes the default's type: an Integer, a Float, `true`/`false` (`1`, `true`, `yes`, `on`), a String; an Array default splits the value on commas. An empty variable counts as unset, or as `nil` with `blank: true`. |
| `path(name, default, env:)` | A setting expanded against the board's root (`root`, the current directory unless set with `root=`). |
| `service(name) { … }` | An instance method that makes the service with the block (evaluated in the domain object) on first use, so one service can use another. |
| `background(name, every: nil, if: nil, **options) { … }` | Work that `start` begins with `BBS.background`: `every` is seconds, a block evaluated in the domain object, or `nil` for once; `if` a block that must answer true for it to begin; the other options are those of `BBS.background`. |
| `env_prefix('X_')` | The prefix when `BBS.board` did not set one (a tool, a test); by default the class name's: `FeediaBBS` → `FEEDIA_BBS_`. |

Instance methods:

- `services` — every service by name, made now: what an Application and a
  `Petscii::Face` get as readers.
- `start` — opens the databases, makes every service and begins the
  background work. `BBS.board` calls it once at boot. Returns `self`.
- `databases` — the board's databases by name (`Sequel::Database` each),
  opened and migrated on first use, the `BBS::Model` classes bound to them.

The class macro `database(setting, migrations, name: :main)` declares a
database: the file of the path setting `setting`, migrated by the
`migrations` list (see [BBS::Model and BBS::Database](#bbsmodel-and-bbsdatabase)).

Keep plain methods for anything else; the domain object is an ordinary
class.

### `BBS::Preset`

What a family of boards has in common and rubbs does not know:

```ruby
TTG_PRESET = BBS::Preset.new(splash: TTG::Logo.splash, url: 'teletypegames.org',
                             qr: 'HTTPS://TELETYPEGAMES.ORG', user_agent: '(+https://teletypegames.org)')
```

| Part | Used for |
|---|---|
| `splash` | A `BBS::Splash` shown after the terminal question (see [Two faces on one port](#two-faces-on-one-port-bbsterminal)). |
| `url` | The "More of us:" address of the goodbye screen. |
| `qr` | The text of the goodbye screen's QR code (`nil`: none). |
| `user_agent` | What follows `rubbs/<version>` in the User-Agent of `BBS::HTTP`. |

Every part is optional. The TTG boards use `TTG::PRESET` from `ttg-common`.

---

## 4. Server lifecycle

### `BBS.configure { |c| … }` / `BBS.config`

`BBS::Config` is the low-level configuration underneath `BBS.board`, which
sets most of it. The `Server` reads it once at boot; per-session state
lives on `BBS::Session`. A board without `BBS.board` (a test, a tool) sets
`flow` itself with `BBS.configure` and calls `BBS.start`.

| Field | Default | Description |
|---|---|---|
| `flow` | — | The root `BBS::Flow` to run for each connection (required). `BBS.board` builds it. |
| `port` | `ENV["BBS_PORT"] \|\| 2323` | TCP port for `BBS::Server`. |
| `title` | `nil` | The board's name as callers read it; set by `BBS.board`. The goodbye screen uses it. |
| `log_tag` | `ENV["BBS_LOG_TAG"] \|\| "bbs"` | What every `BBS.log` line starts with: the board's technical name, `feedia-bbs`; set by `BBS.board` from the title. |
| `env_prefix` | `nil` | The prefix of the board's own environment variables (`FEEDIA_BBS_`), read by `BBS::Domain#setting`; set by `BBS.board`. |
| `preset` | `BBS::Preset::NONE` | The board's `BBS::Preset`. |
| `board` | `nil` | The board's domain object, made once at boot by `BBS.board`: its `services` are the default services of an Application, and a `Petscii::Face` gets it. |
| `mouse` | `false` | If true, sessions enable xterm SGR mouse reporting. `BBS.board` turns it on for a board with a modern face (`mouse false` turns it off). |
| `mouse_on_connect` | `true` | With `mouse`, whether reporting starts on connect. `BBS.board` turns it off on a two-faced board and lets the terminal question switch the mouse on for a modern terminal. Applications and doors still switch it on and off. |
| `idle_seconds` | `nil` | Hard idle-timeout of the Application loop. It is also each connection's socket read/write timeout (900 s when `nil`), so a line that stays silent at a login prompt or inside a door is dropped too. Every session starts with this value; `session.idle_seconds = 3600` changes it for one caller. `BBS.board` sets 600 unless `idle` says otherwise. |
| `max_sessions` | `ENV["BBS_MAX_SESSIONS"] \|\| 100` | Connections served at once; one more is told to try later and closed, and the server logs `BBS busy: …`. |
| `max_sessions_per_ip` | `ENV["BBS_MAX_SESSIONS_PER_IP"] \|\| 6` | Connections served at once from one address; one more is told so and closed (`BBS crowded: …`). Private, loopback and link-local peers (bbs-web proxying many callers from the Docker network) are not limited. |
| `ai_concurrency` | `2` | `BBS::AI::Client` requests running at once in the process; the next waits up to 5 s, then gets `BBS::AI::Busy`. |
| `user_agent` | `"rubbs/<version>"` + the preset's `user_agent` | The `User-Agent` of `BBS::HTTP` requests; `user_agent=` overrides it. |
| `theme` | `nil` | Default `BBS::Theme` for Applications. |
| `screens_dir` | `nil` | Directory for ERB templates used by `Flow#screen` when the flow has no `screens_dir` of its own. |
| `on_session_end` | `nil` | `->(session) { … }` invoked from the server thread after each session ends, even on errors. `BBS.board`'s `on_session_end` sets it. |

### `BBS.start(port: …)`

Boots a `BBS::Server` (one thread per client); `BBS.board` calls it. Each
thread:
1. Creates a `BBS::Session` (assigns a hex `session_id`).
2. Performs Telnet negotiation (SGA, ECHO, NAWS — terminal size).
3. Enables mouse reporting if `BBS.config.mouse` (and `mouse_on_connect`).
4. Runs `FlowRunner.new(session, session_id, BBS.config.flow).run`.

### The length of a call: `BBS.duration`

Every call's context starts with `:started_at`, the time it came in;
`BBS.duration(context[:started_at])` says how long it has lasted, the way a
caller reads it: `45s`, `12m`, `2h 5m` (a number of seconds works too).

### Logging and background work: `BBS.log`, `BBS.background`

Every line the library and the board write to the log goes through one
method, so the lines of eleven boards in one log read the same. The tag is
the board's technical name, which `BBS.board` takes from the title:

```ruby
BBS.log('catalog refresh', 'done in 3.2 s')   # feedia-bbs: catalog refresh: done in 3.2 s
BBS.log('catalog refresh', error)             # feedia-bbs: catalog refresh: SocketError: …
```

Work out of the callers' way (an index loaded at boot, a catalog refreshed
every hour) runs in a `BBS::Background` thread: an error is logged and the
block tried again after `retry_after` seconds, the pause doubling up to
`max_retry`, so a service that is down costs a few log lines, not a crashed
board or a busy loop. A domain object declares it with `background`
([§3](#3-the-board-bbsboard-and-bbsdomain)); underneath it is:

```ruby
BBS.background('index') { wiki.load_index }                     # until it succeeds once
BBS.background('catalog refresh', every: 3600) { library.refresh }
BBS.background('canvas writer', every: 5, retry_after: 5) { canvas.flush }
```

Both return the `Thread`; `BBS::Background.new(…).run` runs the same work in
the calling thread (a test, a command-line tool).

### `BBS::Server`

Lightweight wrapper around `TCPServer`. Catches accept-loop errors (any
`SystemCallError`, `IOError`) and warns instead of crashing; stops on Ctrl-C
and on SIGTERM (`docker stop`) with `Server stopped.`. `#admit(address)` is the
door policy (`:ok`, `:busy`, `:crowded`); a session's slot is given back
whatever ends it.

---

## 5. The Flow layer

`BBS::Flow.define { … }` builds an immutable, line-oriented dialogue. Each
step is a small object (`BBS::Flow::Steps`) that `BBS::FlowRunner` runs with
a shared context hash keyed by Symbol field names. Most boards never write
one: `BBS.board` builds the flow of each face (an `app` or a `face` step,
then `goodbye`). A board writes one for what comes before its face (a
banner, a sign-up), as the block of `modern` or `petscii`.

### Step reference

| Step | Signature | Effect |
|---|---|---|
| `screen` | `screen :name, **vars` | Render the ERB file `name.erb` from the flow's `screens_dir`, or from `BBS.config.screens_dir` (vars resolved against the context if Symbols). |
| `banner` | `banner text, style: :success` | Box-drawing banner. |
| `big_banner` | `big_banner text, style:, font:` | FIGlet (Artii) ASCII art header. `font:` defaults to `'slant'`. |
| `say` | `say text, style: :muted` | Print one line, then blank line. |
| `text` | `text content = nil, style:` / `text(style:) { \|ctx\| ... }` | Print one line; a block gets the context. |
| `ask` | `ask :name, prompt:, transform:, validate:` | Read a line into the context. `transform` is `:upcase`/`:downcase`/`Proc`. `validate` is `:email`/`:non_empty`/`Proc`. On a C64 the answer is typed in a `BBS::Field`. |
| `persist` | `persist :a, :b, store: STORE` | Upsert listed fields into a `BBS::Store`, keyed by `session_id`. |
| `pause` | `pause msg, seconds: 1.0` | Print message and sleep. |
| `gate` | `gate(denied:) { \|ctx\| ... }` | If block returns falsy, print denied msg and halt. |
| `confirm` | `confirm msg, denied:` | Yes/No prompt; halt if "no". |
| `confirm` | `confirm(msg, denied:) { ... }` | Yes/No prompt; on "yes" run the steps of the block. |
| `menu` | `menu(prompt, loop: false) { option … }` | A numbered `BBS::Selector` of the options, `prompt` on its status row. Each option is a list of steps; `loop: true` re-shows after each selection until `exit_menu`; Esc leaves. |
| `exit_menu` | `exit_menu` | Leave the enclosing menu. |
| `call` | `call { ... }` | Arbitrary code, run in the `BBS::FlowRunner`: `session`, `context`, `session_id`, `write`, `line`, `readline(mask:)` are at hand. Return `:halt` to end the flow. A dropped line ends the flow quietly; any other error is logged, the caller is told "Something went wrong." and the flow goes on. |
| `app` | `app DEFINITION` | Run a `BBS::Application` definition (with its doors). |
| `face` | `face FaceClass` | Run a `BBS::Petscii::Face` subclass (or any class made with `new(session, context, board)` that has a `run`). |
| `goodbye` | `goodbye 'note'` | The goodbye screen of the caller's face (`BBS::Goodbye.show`) with the note, then the end of the flow. |
| `flow` | `flow other_flow` | Add the steps of another `BBS::Flow` here. |

```ruby
call { context[:caller_key] = session.caller_key }
```

### Hang-ups: `BBS::Hangup`

A dropped line is `BBS::Hangup`, an `IOError`: rubbs raises it where a read
finds no caller, and a Flow step, an Application and a `Petscii::Face` end
the call quietly on it, so a board never rescues it. `BBS::LINE_DROPPED`
lists the errors of a dropped line (`IOError`, `Errno::EPIPE`,
`Errno::ECONNRESET`) for the rare `rescue *BBS::LINE_DROPPED` that has to
tell them from a bug.

### A flow's own screens

`BBS::Flow.define(screens_dir: path) { … }` keeps the flow's ERB screens
next to it, so a flow shipped in a gem renders its own `screen` steps
inside any BBS, whatever `BBS.config.screens_dir` says. Without it the
flow uses `BBS.config.screens_dir`.

`FlowRunner.new(session, session_id, flow, context: {})` seeds the flow's
context; a door uses it to pass the caller's name in.

### Available styles for `style:` arguments

`:success :muted :error :info :prompt` (`BBS::FlowRunner::STYLES`, colours of
the `BBS::Ansi` palette).

### Validation

`ask … validate: :email` rejects with a built-in message and halts. `:non_empty`
rejects empties. Pass a custom Proc for ad-hoc rules (must return truthy).

### Example — login + menu, then the face

```ruby
BBS.board 'Club BBS', ClubBBS do
  modern do |club|
    screen :welcome, year: Time.now.year
    ask :user, prompt: 'Login', validate: :non_empty, transform: :downcase
    persist :user, store: club.users

    gate(denied: 'Banned user.') { |ctx| !club.banned?(ctx[:user]) }

    menu 'Choose:', loop: true do
      option('Read messages') { call { Messages.new(session, context[:user]).run } }
      option('Enter the club') { app UI::Modern::APP }
      option('Quit') { exit_menu }
    end
  end
end
```

---

## 6. The Application layer

`BBS::Application` is the windowed face: a widget event loop with a
desktop, a menubar, a statusbar, a switchable window stack, mouse, focus
traversal, themes and per-window ticks. It is declared with
`Application.define`; `BBS.board` (or a Flow's `app` step) runs it.

### `Application.define`

```ruby
module UI
  module Modern
    APP = BBS::Application.define do
      theme :synchronet
      helpers { include Helpers }
      init { context[:lang] ||= 'en' }

      command(:search, 'Search…', key: 'F2') { search }            # menu item + key + statusbar hint, once
      command(:random, 'Random article', key: 'F3', hint: 'Random') { random }
      command(:secret, 'Supervisor', key: 'F9', hint: false) { unlock }   # a key without a hint
      menu 'Wiki', :search, :random, :separator, :log_off            # entries: commands, :separator, :doors
      menu('Board') { command :boards; item('Who is online') { who }; doors }
      help about: ABOUT, reading: READING, keys: ['Space        vote']  # Help: About, Reading, Keys
      status { "#{feeds.size} feeds" }                                # right end of the statusbar; clock added

      desktop do
        art  Logo::HALF_BLOCKS, top: 2                              # placed by words, re-placed on resize
        line TAGLINE, bottom: 1
        line(top: 3, align: :right, margin: 2) { "#{feeds.size} FEEDS" }
        widget(height: Pharos::HEIGHT, middle: -12) { Pharos.new }  # made per call; ticked if it has #tick
        button('Master', bottom: 0, align: :right) { master }
        on_show { search }                                           # the first window
      end

      parts ResultsWindow, ArticleWindow                             # modules that `extend BBS::Part`
    end
  end
end
```

Every block of the declaration (a command, a menu item, `init`, `status`,
the desktop's lines and buttons, the window blocks) runs in the
Application: the helpers, the services (as readers by name) and the
instance methods below are called bare.

### `Application.define` DSL

| Method | Purpose |
|---|---|
| `theme(name_or_theme) { … }` | The base theme: a preset name (`:synchronet`) or a `BBS::Theme`. In the block, any one-argument call naming a role (`accent "\e[1;33;40m"`) overrides it; `inherit :neumanntronics` switches the base mid-block, `style :key, "\e[…"` is the explicit form. A block alone starts from `BBS.config.theme`. |
| `services(hash)` | The services of the application, replacing those of the board's domain object. Without any call the application gets `BBS.config.board.services`. Each service is a reader of its name on the application. |
| `helpers { … }` | Module-eval'd: methods defined (or modules included) there become methods of the application and of its window blocks. |
| `init { … }` | Runs in the application after it is built, before the desktop: per-call state (`context[:lang] \|\|= 'en'`). |
| `command(name, label, key:, hint:, about:) { … }` | Something the caller can do, said once: `label` is its menu item (an `&` marks the hotkey; without one the menu picks a free letter), `key` its key anywhere (`'F2'`, `'Alt-R'`), `hint` its word on the statusbar (default: the label without `&` and `…`; `false` binds the key without showing it), `about` the statusbar line while its menu item is highlighted. |
| `menu(label, *entries) { … }` | A menu of the menubar. Entries are command names, `:separator` and `:doors` (one item per door); the block adds more: `command :name`, `item(label, shortcut:, enabled:, hint:) { … }`, `separator`, `doors`. |
| `help(titled = {}, about:, keys:, **pages) { … }` | The Help menu: the block's own items (an ItemsBuilder), `About` showing `about` (a String, or a lambda evaluated when chosen), one item per other page (`reading: READING` becomes "Reading"; a Hash with String titles keeps them: `{ 'Jargon File' => JARGON }`), and `Keys`, written from the commands and rubbs' own keys, with `keys` (lines of the board's own keys) added. |
| `status(clock: true) { … }` | The text at the right end of the statusbar, refreshed every second; the clock (`HH:MM`) follows it, comes first with `clock: :before`, or is left out with `clock: false`. |
| `desktop { … }` | What lies under the windows (below). |
| `window(name, type) { … }` | A declared window, opened with `show(name, **extras)` (see [§11](#11-declared-windows-window-name-type-and-bbswindows)). |
| `door(name, program, label:, hint:)` / `door(a_door)` | A door the caller can step into (see [§20](#20-doors-bbsdoor)); `doors` in a menu lists them. |
| `doors { … }` | Doors made when the application is built (the block runs in it): `doors { board.doors }`. |
| `parts(*modules)` | Replays the declarations of each `BBS::Part` (below). |
| `on_tick { … }` | Runs in the application once a second while the caller is idle, after the status is refreshed (an animation, a poll). |
| `on_idle { … }` | Runs in the application when the caller reaches the idle limit. Calling `keep_on` in it keeps them on (a "still there?" dialog that got an answer); otherwise the line drops. |
| `on_door { \|door, context\| … }` | Runs just before the line goes to a door (who is where, a log line). |

Built-in commands: `:menu` (F10, opens the first menu; only with a
menubar) and `:log_off` (Alt-X, label `Log off`, hint `Bye`). Name them in
a menu like any command (`menu 'Wiki', :search, :separator, :log_off`);
declaring a command of the same name replaces one in its place. A `key` may be an F-key, `Alt-X`, `Ctrl-S`, `Esc` or `Tab`.

### The desktop

```ruby
desktop do
  art     Logo::HALF_BLOCKS, top: 2
  line    TAGLINE, bottom: 1
  line(top: 3, align: :right, margin: 2) { "#{feeds.size} FEEDS" }
  widget(height: Pharos::HEIGHT, middle: -10) { Pharos.new }
  button('Master', bottom: 0, align: :right) { master }
  on_show { search }
end
```

| Item | What it is |
|---|---|
| `art(lines, style: :accent, **place)` | Lines drawn as one block (a logo). |
| `line(text, style: :text_dim, **place)` / `line(**place) { … }` | One line; a block gives the text, evaluated in the application at every repaint. |
| `widget(height: 1, fill: false, **place) { … }` | A `BBS::Widget` of the board, made by the block for each call, or filling the whole desktop with `fill: true`; one with a `tick` method is ticked once a second. |
| `button(label, **place) { … }` | A button that runs the block in the application. |
| `on_show { … }` | Runs once the desktop is up: the first window or dialog. |

Items are placed by words, in rows of the desktop: `top: n` (from the top),
`bottom: n` (from the bottom), `middle: n` (from the middle, negative
above); across, `align:` `:center` (default), `:left` or `:right`, with
`margin:` columns from that edge. They are placed again when the terminal
changes size. `app.desktop.widget(0)` is the first board widget made.

### Parts: `BBS::Part`

A piece of the declaration in a file of its own: a module that extends
`BBS::Part` and declares with the same words as `Application.define`
(`window`, `command`, `menu`, `helpers`, `door`, …); `parts` replays them.

```ruby
module UI::Modern::ArticleWindow
  extend BBS::Part

  window :article, :master_detail do
    title { article.title }
    items { article.sections }
    label :title
  end
end
```

### Application instance API

What helpers, commands and window blocks call on the application.

| Method | Purpose |
|---|---|
| `cols`, `rows` | Terminal size from NAWS (defaults 80×24). |
| `theme` / `context` / `session` / `services` | Live state; each service is also a reader of its name (`feeds`). |
| `message(text, title: 'Message', width: nil)` | A message box with OK. Returns the window. |
| `ask(prompt, title: 'Input', value: '', width:) { \|text\| … }` | A box asking for a line; OK (or Enter) runs the block with the text, unless it is blank. |
| `confirm(text, title: 'Confirm') { … }` | A Yes/No box; Yes runs the block. |
| `loading(text = 'Working…', failed: nil, title: 'Sorry') { … }` | Runs the block in a thread under a "Please wait" box and returns its value. With `failed:`, a `nil` value or an error is told to the caller as `failed` (in a box titled `title`) and ends the command (`BBS::Abort`); without it the value comes back as it is and an error is raised. |
| `fail_with(text, title: 'Sorry')` | Tells the caller `text` in a message box and ends the command (`BBS::Abort`). |
| `report(result, messages, title: 'Message')` | Tells the caller what `result` (a Symbol a domain service answered) means: its text in `messages`, when there is one. Returns `result`. |
| `qr(text, title: 'QR code')` | `text` (an address) as a QR code in a window as big as the screen allows: with a quiet zone when it fits, without one when only that fits, else a message that the screen is too small. |
| `show(name, **extras)` | Opens the declared window `name` with `extras`, or pushes a `BBS::Window`. |
| `window(name)` | The open window declared as `name` (the frontmost), or `nil`: `window(:browser)&.selected`. |
| `close_all` | Closes every window. |
| `reload_details` | Redraws the detail pane of every open master/detail window, after the data under them changed. |
| `markdown(text, width = cols - 4)` | Markdown as lines in the theme's colours (`BBS::Markdown`). |
| `caller_key` | The key the caller is known by for rate limits (`session.caller_key`). |
| `board` | The board's domain object (`BBS.config.board`). |
| `refresh_status` | Rewrites the right end of the statusbar now (the `status` block and the clock), e.g. after a setting changed. |
| `log_off` | Ends the application: the flow goes on to the goodbye. Returns `:halt`. |
| `dim(s)`, `bright(s)`, `accent(s)`, `paint(role, s)` | `s` in a theme role, back to the plain text colour after it (`BBS::Paint`; a `Petscii::Face` has the same words). |
| `with_line { \|session\| … }` | Hands the raw line to the block on a clean screen without mouse reporting (`session.hand_over`), then repaints everything; returns the block's value. For a file transfer or a gateway. |
| `open_door(name)` | Leaves through a declared door: returns `:halt`, and the application's run opens the door and builds the application again afterwards. |
| `open_window(window_or_name, **extras)`, `close_window(window)`, `top_window`, `raise_window(window)`, `cycle_windows(step)` | The window stack underneath `show` and `close_all`. |
| `add(widget)` | Appends a widget to the root container behind the windows. |
| `tick!`, `stop!` | Fire the periodic tick by hand; break out of the run loop. |

```ruby
module Helpers
  NO_ANSWER = 'Wikipedia did not answer. Try again later.'

  def search
    ask('Article title:', title: 'Search', width: 60) { |text| read(text) }
  end

  def read(title)
    article = loading('Loading the article…', failed: NO_ANSWER) { articles.article(title, lang: lang) }
    show(:article, article: article)
  end
end
```

`BBS::Abort` ends the command the caller started (a menu item, a key, a
button) without an error: `loading … failed:` and `fail_with` raise it after
telling the caller, and the event loop takes it quietly, so the caller stays
where they were. Titles are plain (`title: 'Search'`): the frame pads and
cuts them.

### Run loop

`run` does:

1. Render full frame, diff against the committed buffer, write the delta.
2. Wait for a key (`Session#readkey(timeout: 1.0)`).
3. On `:idle` — fire `tick!` (which refreshes the status, runs the
   `on_tick` block, ticks the desktop's widgets and `window.tick(self)` for
   every open window), then check the idle-disconnect timeout: at the
   session's `idle_seconds` the `on_idle` block runs, and unless it calls
   `keep_on` the loop shows a message and ends.
4. Otherwise build an `Event` and dispatch (top window → menubar → statusbar
   → root focus manager).

Returning `:halt` from a handler (or `log_off`) ends the application, and
the flow goes on to the goodbye. An exception in a handler is logged and
the event dropped: it does not end the caller's session; a `BBS::Abort` is
not even logged.

`Builder#run(session:, session_id:, context:)` is `build(...).run` that also
takes the caller through doors: when the application ended with `open_door`,
it runs the door and builds the application again, until the caller leaves
without one.

---

## 7. The line-by-line face: `BBS::Petscii::Face`

The face of a Commodore 64 (40×25 PETSCII), or of a modern terminal line by
line, declared in a subclass: its title bar, its masthead and its main
menu; its own methods say what each item does.

```ruby
module UI
  class Petscii < BBS::Petscii::Face        # the C64 colours, COLS, WIDTH are its constants
    title('FEEDIA BBS') { "#{feeds.size} feeds" }

    masthead do
      art  PICTURE                          # lines as they are
      logo 'FEEDIA', colors: LOGO_COLORS    # BlockFont.petscii
      rule
      line 'all the news that fits', color: WH
    end

    main_menu do                            # main_menu(back: 's') when ← should not log off
      heading 'reading'
      item('f', 'feeds', 'the list of feeds') { feed_list }
      item('l', -> { "language: #{lang}" }, 'the next one') { next_language }   # a label that changes
      log_off 'hang up. see you!'
    end

    private

    def feed_list
      each_pick('FEEDS', feeds.list, label: :title) { |feed| read(feed) }   # the title comes back by itself
    end
  end
end
```

`BBS.board` (or a Flow's `face` step) makes one per call with the session,
the context and the board's domain object, whose services become readers of
the face, and calls `run`: the masthead, then the main menu until the caller
logs off. The C64 colours (`WH YE CY LG GR DG LB BL GN RD PU OR`, `RV RO`,
see `BBS::Petscii::Colors`), `COLS` and `WIDTH` are constants of every
subclass, so classes nested in it see them too.

### The declaration

| Class method | What it declares |
|---|---|
| `title(text) { … }` | The home title bar: `text`, and the block's text (evaluated in the face) at its right end. |
| `masthead { … }` | What the call starts with, on a cleared screen: `art(lines)` (lines as they are), `logo(word, colors:, glyphs: {}, indent: 2)` (`BBS::BlockFont.petscii`, one colour per row), `line(text, color: LG, indent: 1)` or `line { … }`, `rule` (a dim rule across), `gap(count = 1)` (empty lines). The first main menu goes under it. |
| `main_menu(hint: MENU_HINT, back: nil, home: :title, above: nil, gap: :before) { … }` | The main menu, a `BBS::Selector`: `item(key, label, about = nil, color: nil, if: nil) { … }` (a label or an about may be a lambda, for one that changes; `if` hides the item when it answers false; the block runs in the face), `each_of(source) { \|object, i\| item(…) }` (items made each round from what the lambda `source` gives), `heading(label = '')`, `log_off(about, label: 'log off', key: 'q')`. `back` is the key of the item ← (RUN/STOP) takes; by default the log-off item. `home` is what each round draws above the menu: the home title bar, or `:masthead`; `above` a lambda whose lines come above the menu; `gap` where the empty line goes (`:before` those lines, `:after`, or `false`). An item without a block only returns its key from `main_menu_choice`. |

A sub-menu is declared like the main menu and run from an item:

```ruby
sub_menu(:jargon, title: 'THE JARGON FILE', right: '4.4.7') do
  item('1', 'word of the day', 'the same for everyone today') { word_of_the_day }
  back 'to the main menu'
end

main_menu do
  item('j', 'the jargon room', 'hacker slang') { sub_menu(:jargon) }
  log_off
end
```

Each menu's cursor starts on the item taken last from it. A `BBS::Abort` in an
item (from `fail_with` or `loading … failed:`) leaves the caller at the menu.

### Another shape: overriding `run`

`run` is `show_masthead`, then `main_menu_loop`. A face with another shape
overrides it with the same pieces: `home` (the home title bar),
`show_masthead`, `main_menu_choice` (the menu once; `:log_off` when the
caller logs off, the key of an item without a block), `main_menu_loop`.

```ruby
def run
  context[:lang] ||= articles.languages.first
  show_masthead
  loop do
    query = prompt(language_name, hint: 'return alone: menu', max: 80)
    next look_up(query) if query
    break if main_menu_choice == :log_off
  rescue BBS::Abort
    home
  end
end
```

### The face's methods

The face answers the methods of its `BBS::Petscii::Screen` itself (see
[The screen of a line-by-line board](#the-screen-of-a-line-by-line-board-bbspetsciiscreen)):

| Method | What it does |
|---|---|
| `puts`, `say(text, color:)`, `write`, `cls`, `bell` | Text out; `say` wraps a paragraph to 38 columns. |
| `title(text, right)` / `title` | A reversed title bar on a cleared screen; without arguments the home one. |
| `rule`, `rule_line` | A dim rule written, or as a line for a list of lines. |
| `page(heading, lines, right:, wait:, room:, numbers:)` | Lines a screenful at a time under a title. |
| `pick(heading, items, …) { … }`, `each_pick(heading, items, label:, **options) { \|item\| … }` | A numbered list; `each_pick` again and again until the caller goes back, the title put back after each (`items` may be a lambda, read each round). |
| `menu`, `actions`, `choose` | A cursor menu at the cursor, a row of keys, one key of a few. |
| `ask`, `prompt(label, hint:, text:, max:, mask:)`, `edit` | A line field (`prompt` returns `nil` for an empty answer), the full-screen editor. |
| `alert(text, color: RD)`, `notice(text)` | Red (or `color`) / green, then a pause. |
| `confirm?(question)`, `number(label, range)` | y/n; a whole number in a range or `nil`. |
| `pause`, `key` | Wait for a key; read one (`BBS::Hangup` when the line drops). |
| `within(title, right) { … }` | Runs the block under a title, then puts the previous title back. |
| `markdown(text)` | Markdown as lines in the C64 colours, indented. |
| `qr(url)` | A QR code in the middle of the screen, or an alert when it does not fit. |
| `loading(text = 'working…', failed: nil) { … }` | Says `text` dimmed, runs the block; with `failed`, a `nil` value or an error ends the command with `fail_with(failed)`. |
| `fail_with(text)` | `alert(text)`, then `BBS::Abort`. |
| `report(result, messages)` | The text of `result` in `messages`: green for `:ok`, red otherwise. |
| `open_door(door)` | Hands the line to a `BBS::Door` and back. |
| `caller_key` | The key the caller is known by for rate limits. |
| `make_screen(session)` | Override for a screen of its own class or size (a `BBS::Petscii::Screen` by default). |
| `each_pick` + `BBS::Abort` | An Abort in an `each_pick` block (`fail_with`, `loading … failed:`) leaves the caller at that list. |
| `dim`, `bright`, `accent`, `paint(role, text)` | The roles of `BBS::Paint` in the C64 palette (`Face::ROLES`). |
| `screen`, `session`, `context`, `board` | The screen, the line, the call's context, the domain object. |

---

## 8. Full-screen pages: `BBS::Pages` and `BBS::Page`

A full-screen "page app" for both faces: a stack of `BBS::Page` objects,
the top one on the screen. The runner reads the keys, gives each to the
page (and to its own key map after), repaints after it by sending only the
cells that changed, and runs the timers of `every` while the caller is
silent.

On a modern terminal a page draws into a `BBS::FrameBuffer` the size of the
terminal (1-based cells) and the runner writes its `diff`; on a C64 (a
session in PETSCII mode, or `face: :petscii`) it draws into a
`BBS::Petscii::Canvas` (0-based) in `charset` and the runner writes the
canvas's `diff` raw.

```ruby
class Board < BBS::Page
  key(:enter, 'd')  { hand_over { dial(board) } }
  key('b')          { show(Banner.new(board)) }
  key(:escape, 'q') { back }

  def initialize(board) = @board = board

  def draw(screen)
    print_lines(screen, [@board.name, '', 'RETURN dials   Q back'], x: 3)
  end
end

BBS::Pages.new(session).run(Board.new(board))
```

### A page

| Method | What it is |
|---|---|
| `draw(screen)` | Draws the page on a fresh screen for every repaint: a `FrameBuffer` or a `Petscii::Canvas`. It should only draw. |
| `enter` | Called when the page comes on top by `push`, `replace` or `reset`. |
| `resume` | Called when the page is on top again after the one over it went `back`: the place to reload what that one may have changed. |
| `handle(key)` | Answers a key with the class's key map; returns the binding that took it, `nil` when none did. |
| `push(page)`, `back`, `replace(page)`, `quit(value)` | Navigation, by the runner. |
| `show(page) { \|key\| … }` | Shows `page` over this one until the block answers a key with something not `nil` (`false` counts); without a block the first key is the answer. |
| `read_line(label, text:, max:, hint:)` | Reads a line (a `BBS::Pages::Line`, kept in `pages.line` while it is read, so the screen can draw it); the text on RETURN, `nil` when given up. |
| `hand_over { … }` | Gives the screen and the keys to the block (a gateway, a banner played as it came); the next repaint is the whole screen. |
| `redraw(whole: false)` | Repaints now. |
| `print_lines(frame, lines, x:, y:, limit:, clear:)` | Writes lines of ANSI text into a `FrameBuffer`, one a row. |
| `session`, `pages` | The line and the runner. |

### Keys and timers: `BBS::Pages::Keymap`

```ruby
class ListPage < BBS::Page
  key(:up)        { move(-1) }
  key('q', 'Q')   { back }
  key(/\A\d\z/)   { |digit| open(digit.to_i) }
  every(0.5)      { redraw }
end
```

`key(*keys) { |key| … }` binds Symbols (`:up`, `:enter`, `:escape`, see
`Session#readkey`), one-character Strings (case counts) or Regexps that
match a String key; the block runs in the instance and can call `pass` to
leave the key to the next binding. `every(seconds) { … }` runs while the
page is shown and the caller is silent. Both are inherited, a subclass's
own keys looked at first. `cursor(row, col)`, called while drawing, says
where the caller's cursor rests after a repaint.

### The runner

`BBS::Pages.new(session, face: nil, charset: :upper)`: `face` is `:modern`
or `:petscii` (default `:petscii` on a PETSCII line), `charset` the canvas's
character set on a C64 (`:upper` or `:lower`). `run(page)` runs from
`page` until `quit` (returning its value) or until the caller is silent
past the session's idle time while a timer polls (`nil`); a hang-up raises
`BBS::Hangup`. `start(page)` and `press(key)` drive it one key at a time,
for a test. Navigation: `push`, `back` (with one page left, `quit`),
`replace`, `reset`, `quit`; `page` is the one on top, `stack` all of them.

A subclass is the app around the pages: it draws a frame around them
(`draw`, calling `super`), takes keys before the page (`handle`), and
declares keys of its own for the ones no page takes, and timers:

```ruby
class Gate < BBS::Pages
  key('q') { quit }
  every(0.5) { redraw }

  def draw(canvas)
    canvas.text(0, 1, Time.now.strftime('%H:%M'), :grey)
    super
  end
end

Gate.new(session, charset: :lower).run(Home.new)
```

`BBS.board` takes as a face any class made with `new(session, context,
board)` that has a `run`, so a page app is a face through a small class:

```ruby
class GateFace
  def initialize(session, _context, board) = (@session, @board = session, board)

  def run = Gate.new(@session, charset: :lower).run(Home.new(@board))
end

BBS.board 'Gate BBS', GateBBS do
  modern  GateFace
  petscii GateFace
end
```

---

## 9. Widgets

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

### Containers

`Container#add(child)`, `#remove`, `#clear`, `#find(id)`, `#walk { |w| … }`,
`#focusable_descendants`, `#hit_test(x, y)`. Theme propagates to children. A
`BBS::Window` is the container a board lays its widgets out in.

## 10. Windows

`BBS::Window < Container` — a top-level container with title bar, shadow,
close gadget, and its own `FocusManager`. Windows stack; the top one is the
active one and gets the input first, and the caller can switch between them
(see *Switching windows* below).

```ruby
win = BBS::Window.new(title: 'Inbox', modal: false,
                      shadow: true, close_key: :escape,
                      on_close: ->(w) { puts 'closing' })
win.layout(10, 5, 60, 18)
win.add(some_widget)
win.reset_focus
show(win)                                  # Application#show takes a Window too
```

A board usually declares its windows instead (see [§11](#11-declared-windows-window-name-type-and-bbswindows));
`BBS::Window` is for a window of its own kind.

| Field | Default | Description |
|---|---|---|
| `title` | `nil` | Centered title in the top border; plain text, the frame pads it and cuts it to fit. |
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

A window with `maximizable: true` (a declared window: on by default for
master/detail, stream and reader; `maximizable true` in the spec for others)
that is `resizable?` gets a zoom gadget in its top right corner, Turbo Vision
style: `[↑]` fills the desktop between the menubar and the statusbar
(`app.desktop_rect`), `[↕]` puts it back. **F5**, **Alt-Enter** and a
**double click on the title bar** do the same; `toggle_maximize` does it from
code and `maximized?` tells. A maximized window stays maximized when the
terminal is resized.

`resizable?` windows are `MasterDetail`, `Stream`, `Reader`, `Form` (a single textarea
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

## 11. Declared windows (`window :name, :type`) and `BBS::Windows`

A board declares its windows in `Application.define` (or in a `BBS::Part`)
and opens them by name with `show`. The spec block is evaluated in a
`BBS::WindowSpec`; each attribute takes a value or a block.

```ruby
module UI::Modern::ArticleWindow
  extend BBS::Part

  window :article, :master_detail do          # the type is the 2nd argument
    title      { article.title }              # the extras of `show` are methods
    list_width { [26, cols / 4].max }         # or 1/3r; a negative height counts from the screen's
    items      { article.sections }
    label      :title                         # a Symbol, or a block |item|
    detail     { |section, width| markdown(section.markdown, width) }   # lines; rubbs wraps long ones
    meta       { |section| "#{article.url} · CC BY-SA" }
    on_pick    { |section| read_more(section) }    # Enter on the list
    action('QR code') { |section| qr article.short_url, title: 'Scan the article' }
  end
end

show :article, article: found
```

### Where the blocks run: `BBS::WindowContext`

A block runs when the window opens (or, for the callbacks, when the caller
acts) in a `BBS::WindowContext`:

- the application: its helpers, services and methods are called bare
  (`markdown`, `qr`, `articles`, `cols`);
- the `extras` of `show` as methods (`show :article, article: a` → `article`);
- `window` (the window, once open), `selected` (the selected item of a
  master/detail), `form` (the form whose `on_submit` runs), `close`,
  `keep` and `error!` (below); `extras` is the Hash, `app` the application.

An extra may not be named like a method of the application: `show(:x,
rows: 3)` raises `ArgumentError` ("window extras named like application
methods"), so a helper never hides an extra or the other way round. Name it
otherwise (`line_count:`).

### Types and attributes

| Type | Window | Attributes |
|---|---|---|
| `:info` | `BBS::Windows::Info`: text and buttons | `body`, `scroll`, `padding`, `button` |
| `:form` | `BBS::Windows::Form`: fields and Save/Cancel | `field`, `hint`, `prefill`, `on_submit`, `on_cancel`, `errors`, `submit_label`, `cancel_label` |
| `:master_detail` | `BBS::Windows::MasterDetail`: a list and the picked item | `items`, `label`, `detail`, `meta`, `on_pick`, `action`, `list_width`, `empty`, `close_button`, `close_label` |
| `:stream` | `BBS::Windows::Stream`: a log and an input line | `lines`, `placeholder`, `buffer_size`, `on_submit`, `on_poll`, `close_button`, `close_label` |
| `:reader` | `BBS::Windows::Reader`: a long text to page through | `lines`, `where`, `max_width`, `action` |

Every type takes:

| Attribute | Notes |
|---|---|
| `title` | Plain text; the frame pads it and cuts it. |
| `width`, `height` | Columns and rows; a negative number counts back from the screen's size (`height -8` = rows − 8). |
| `maximizable` | On by default for `:master_detail`, `:stream` and `:reader`; `maximizable false` turns it off, `maximizable true` turns it on for the others. |
| `accent` | A Hash of frame style roles (`window_border`, `window_title`, `window_title_focused`) in other colours than the theme's: the window's frame wears them, its widgets keep the theme. Marks which part of the board a window belongs to. |

The attributes of each type:

| Attribute | Type | Value or block |
|---|---|---|
| `body` | info | Body items (see `Windows::Info` below). |
| `scroll` | info | `true`: the whole body in one scroll view. |
| `padding` | info | `{ sides:, top:, bottom: }`. |
| `button(label, **opts) { … }` | info | A button in place of OK. The block runs, then the window closes unless the block calls `keep`. |
| `field(key, **opts)` | form | A field descriptor (`label`, `type`, `max_length`, `rows`, `password`, …); a `value` block is evaluated when the form opens; a field without a value takes it from `prefill`. |
| `prefill { … }` | form | A Hash of field values. |
| `hint`, `submit_label`, `cancel_label` | form | |
| `on_submit { \|values\| … }` | form | Runs on Save. Returning a key of `errors` shows its message and keeps the form open; `error!('…')` does the same with any text; `keep` keeps it open; otherwise it closes. |
| `errors(key: 'message', …)` | form | The messages of the refusals `on_submit` may return. |
| `on_cancel { … }` | form | |
| `items { … }` | master_detail | The list. |
| `label` | master_detail | How an item is named: a Symbol (a method of the item) or a block `\|item\|`. |
| `detail { \|item, width\| … }` | master_detail | The lines of the picked item; rubbs wraps the long ones. |
| `meta { \|item\| … }` / `meta 'text'` | master_detail | The line under the detail. |
| `maximized true` | all | Opens the window full screen. |
| `on_pick { \|item\| … }` | master_detail | Enter (or a double click) on the list. |
| `action(label, **opts) { \|item\| … }` | master_detail | A button under the list, run with the selected item (not on an empty list; a block without a parameter runs always); the window stays open unless the block calls `close`. `opts` are those of `ButtonBar` (`align`, `key`). An `&` is put before the label when it has none, so its first letter is the hotkey. |
| `list_width` | master_detail | Columns, or a Rational of the screen's width (`1/3r`). |
| `empty` | master_detail | The text of an empty list. |
| `lines` | stream | The lines it starts with. |
| `placeholder`, `buffer_size` | stream | The input's placeholder; the most lines kept (500). |
| `on_submit { \|text\| … }` | stream | Enter on a non-empty line; the input is cleared after it. |
| `on_poll { … }` | stream | Every second while idle: an Array of new lines (or `nil`). |
| `lines { \|width\| … }` | reader | The text, made for the width it gets (again when the width changes), or an Array. |
| `where { \|view\| … }` | reader | The position line under the text (default "line a/b · n%"); `view` is the `Widgets::ScrollView`. |
| `max_width` | reader | The widest the window gets. |
| `action(label) { \|reader\| … }` | reader | A button; the block gets the reader (`reader.jump(index)`, `reader.lines = …`, `reader.reload`). |
| `on_key(left: ->(reader, key) { … })` | reader | The reader's own keys, before the text sees them. |

```ruby
window :compose, :form do
  title  { "Post to #{board.title}" }
  width  70
  field  :body, type: :textarea, max_length: 1000
  prefill { { body: draft&.body || '' } }
  errors empty: 'Write something first.', too_fast: 'One post a minute, please.'
  on_submit { |values| posts.add(board.id, caller_key, values[:body]) }   # :ok closes, :empty / :too_fast refuse
end

window :rfc, :reader do
  title     { "#{rfc.name}: #{rfc.title}" }
  max_width 78
  lines     { |width| styled(rfc, width) }
  action('Contents') { |reader| contents(reader, rfc) }
end

window :about, :info do
  title  'About'
  body   [{ text: 'News BBS', style: :accent, align: :center }, :spacer, ABOUT]
  button('Show the QR code') { qr 'https://example.org' }
  button('Close')
end
```

Block attributes are evaluated each time the window opens, so they reflect
the current extras and state.

### `BBS::Windows`: the window classes

The declared windows are these classes. A board can also open one
imperatively with `.open(app, …)` from a helper, for a window that is not
worth a name; the options are those of each class's RDoc.

#### `BBS::Windows::Info`

Centered info / splash / message dialog.

```ruby
BBS::Windows::Info.open(app,
  title: 'Welcome',
  width: 70, height: 20,
  body: [
    { text: 'rubbs v2.0', style: :accent, align: :center },
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

#### `BBS::Windows::Form`

Labeled multi-row form with inline validation. Field types: `:input`
(default, single-line `TextInput`), `:textarea` (multi-line, label ignored;
one without `:rows` takes the height left over), `:checkbox` (label part of
widget). In the form: `values` (the field values as a Hash), `error('msg')`
(the status line red), `info('msg')` (the status line in the input label
colour; `info('')` wipes it). Buttons: a `[ &Save ]` / `[ &Cancel ]` pair
by default (`submit_label`, `cancel_label`).

#### `BBS::Windows::MasterDetail`

Two-pane browser: ListBox on the left, ScrollView on the right. The detail
is drawn whenever the selection changes. A `[ &Close ]` button is appended
unless `close_button: false`; the actions render to the left of it.
`replace_items(items, title: nil)` swaps the list in place and selects the
first item (a file browser changing folders); `reload_detail(keep_scroll:
true)` redraws the detail after its data changed (`reload_details` on the
application does it for every open one). Exposes `list_widget`,
`detail_view`, `meta_label`.

#### `BBS::Windows::Stream`

Scrolling history pane + single-line input + idle-tick polling, for chat and
log views. `buffer_size` caps the in-memory history (older lines drop off).
Exposes `history` (ScrollView) and `input` (TextInput).

#### `BBS::Windows::Reader`

A long text to read: its lines in a scroll view (arrows, PgUp/PgDn,
Home/End, the wheel), a line under it that says where the reader is, and
buttons (Close added). As wide as the desktop allows up to `max_width`, as
tall as the desktop less a row above and below; resizable and maximizable.
`jump(index)` moves the text so that line `index` (0-based) is the second
row; `lines = new_lines` replaces the text and goes to the top; `view` is
the scroll view.

#### `BBS::Windows::ButtonBar`

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
open after a click; otherwise it closes. The declared windows' `action`s
are `keep_open` buttons.

---

## 12. Dialogs

In an Application the dialogs are its methods: `message(text, title:)`,
`ask(prompt, title:) { |text| … }`, `confirm(text) { … }` and `loading(text)
{ … }` (see [§6](#6-the-application-layer)). Underneath are the helpers of
`BBS::Dialogs`, for code outside an application's blocks:

```ruby
BBS::Dialogs.message(app, 'Saved!', title: 'Done', width: 40)

BBS::Dialogs.confirm(app, 'Delete this message?',
  on_yes: -> { Msg.delete(id) },
  on_no:  -> { … })

BBS::Dialogs.input(app, prompt: 'New name:', value: '',
  on_submit: ->(value) { rename(value) })   # Enter in the field is OK
```

`BBS::Dialogs.centred_window(app, width:, height:, title:)` is the underlying
helper to build a centered, modal `Window`.

For richer windows declare a window
(see [§11](#11-declared-windows-window-name-type-and-bbswindows)).

---

## 13. Menubar, Statusbar, Focus

The menubar and the statusbar of an Application are written from its
commands: a command is said once, and its menu item, its key and its hint
on the statusbar come from it.

### `BBS::Menubar`

```ruby
command(:open, 'Open…', key: 'F3') { open_file }
command(:save, 'Save',  key: 'F2', about: 'Write the file to disk') { save }
command(:find, 'Find…', key: 'F7') { find }
menu 'File', :open, :save, :separator, :log_off
menu('Edit') do
  item('Undo', enabled: -> { history.any? }) { undo }
  separator
  command :find
end
help about: 'My editor, a rubbs board.'
```

- Each `menu` adds a menu; `help` adds the Help menu last (About, the other
  pages, Keys).
- An `&` in a label marks the hotkey letter (Alt+letter from anywhere, plain
  letter while the menu is open). A label without one gets one: the first
  letter not taken in that menu. A menu's own label gets one the same way.
- A command's `key` is drawn on the right of its item and works anywhere.
- A command's `about` (an item's `hint:`) is a line about it: while the item
  is highlighted, the statusbar shows it in place of its hints. A door's
  `hint:` does the same for its item under `doors`.
- `enabled:` takes a block, evaluated in the application each time the menu
  opens.
- F10 (the built-in `:menu` command) opens the first menu; Esc closes.
- The blocks run in the application. Returning `:halt` (or calling
  `log_off`) ends the face.

When the menubar is open, all events are routed to it first — its keys cannot
leak through to underlying windows.

### `BBS::Statusbar`

Every command with a `key` shows its hint on the statusbar, left-aligned,
the built-in ones after the board's (`F10 Menu`, `Alt-X Bye`); `hint:
false` keeps the key working without showing it. The right end is the
`status` block's text and the clock, refreshed every second
(`refresh_status` does it at once).

While `statusbar.message` is set, the bar shows that line instead, across
its whole width; the Application sets it to the hint of the highlighted menu
item (`Menubar#selected_hint`) on every render. A mouse click on a hint
runs its command. Key matching is forgiving: `F10` → `:f10`, `Alt-X` →
`:alt_x`, `Esc` → `:escape`, `Tab` → `:tab`, anything else uses
case-insensitive name match.

### `BBS::FocusManager`

One per `Window` (and the application's root container). Walks visible,
enabled, focusable descendants for Tab / Shift-Tab cycling.

Key behavior:

- `handle_focus_key(event)` — consumes Tab / Shift-Tab.
- `focus(widget)` — explicit focus (used when a window opens to put cursor
  on the first input).
- `dispatch(event)` — forwards to the focused widget's `handle_event`.

---

## 14. Theming, the palette and `BBS::Style`

A `BBS::Theme` maps style roles to ANSI SGR strings. The presets are data,
one Hash each in `BBS::Theme::PRESETS`, and `BBS::Theme.fetch(name)` builds
one (`Theme.synchronet` and the others are shorthands for it).

Built-in presets:

| Preset | Vibe |
|---|---|
| `BBS::Theme.synchronet` (default) | Yellow on black, blue windows — Synchronet-style. |
| `BBS::Theme.nortoncommander` | Blue screen, cyan title bar — Norton Commander. |
| `BBS::Theme.dosnavigator` | Light grey background, white panels — DOS Navigator. |
| `BBS::Theme.neumanntronics` | Muted 256-color palette, dark cyan accents. |
| `BBS::Theme.mono` | Black & white, inverse-video selections — terminals without color. |

### Style keys

`BBS::Theme::ROLES`, the roles every preset defines (a theme with any other
role is refused):

`screen`, `text`, `text_dim`, `text_bright`, `label`, `accent`, `success`,
`error`,
`window_bg`, `window_border`, `window_title`, `window_title_focused`,
`window_text`, `window_shadow`,
`menubar`, `menubar_hotkey`, `menubar_selected`, `menubar_sel_hot`,
`menu_bg`, `menu_text`, `menu_hotkey`, `menu_selected`, `menu_disabled`,
`menu_border`,
`statusbar`, `statusbar_key`,
`button`, `button_focused`, `button_hotkey`, `button_disabled`,
`input`, `input_focused`, `input_label`,
`listbox`, `listbox_selected`, `listbox_focused`,
`scrollbar`, `scrollbar_thumb`.

### Customising

```ruby
# 1. Use a preset
theme :synchronet

# 2. Override per-key with the DSL block
theme :nortoncommander do
  inherit :neumanntronics            # optional: switch base mid-block
  window_border "\e[1;36;44m"
  accent        "\e[1;33;44m"
  style :screen, "\e[40m"            # explicit form
end

# 3. Build from scratch (every role of BBS::Theme::ROLES)
theme BBS::Theme.new(:mine, BBS::Theme::PRESETS[:mono].merge(screen: "\e[40m"))

# 4. Merge in code
custom = BBS::Theme.synchronet.merge(accent: "\e[1;36;40m")
```

`Theme#style(key)` / `Theme#[](key)` look up a SGR. Widgets call
`style(:role)` which resolves through the widget's `theme` or its parent's.

### The palette

Every colour outside a theme comes from one palette, `BBS::Ansi`: `GREY`
(plain text), `DIM_GREY`, `DARK_GREY`, `WHITE`, `BRIGHT_RED`, `GREEN`,
`BRIGHT_GREEN`, `YELLOW`, `BRIGHT_YELLOW`, `BLUE`, `BRIGHT_BLUE`, `MAGENTA`,
`CYAN`, `BRIGHT_CYAN`, plus `REVERSE`/`REVERSE_OFF` and `RESET`.
`BBS::Petscii::Colors` are the C64 names of the same sequences (`WH YE CY LG
GR DG LB BL GN RD PU OR`, `RV RO`), and a component takes a role Hash of
them: `BBS::Selector::COLORS` (`text key bar heading about hint`), the
Flow's `FlowRunner::STYLES`, a FakeOS's `colors`. On a canvas the same roles
turn into C64 codes (`BBS::Petscii::Canvas.color(YE) == Canvas::YELLOW`).

The roles of `BBS::Paint` (`dim`, `bright`, `accent`, `paint(:error, s)`)
are the same words on both faces: an Application paints with its theme's
`text_dim`, `text_bright`, `accent` …, a `Petscii::Face` with the C64
palette (`Petscii::Face::ROLES`), so a line built with them reads the same
on either.

### `BBS::Style`: SGR by colour

A board names its own colours once by what they are, not by their escape
sequence, and writes the names. A style is a frozen String, so it goes into
text as it is and into a `BBS::FrameBuffer` as an `sgr:`.

```ruby
ACCENT = BBS::Style[fg: 84]                       # "\e[38;5;84m"
LIT    = BBS::Style[fg: 84, bg: 16, bold: true]
WARN   = BBS::Style[fg: :bright_red, bold: true]  # "\e[1;91m"
SKY    = BBS::Style[fg: [120, 180, 255]]          # true colour
session.write(BBS::Style.paint(ACCENT, 'Online')) # the style, the text, BBS::Style::RESET
```

`fg:` and `bg:` take an xterm-256 index (0–255), a name (`black red green
yellow blue magenta cyan white default`, `bright_` before it for the
bright one) or `[r, g, b]`; the attributes are `bold faint italic underline
blink reverse`, each `true` when wanted. An unknown colour or attribute
raises `ArgumentError`. A FakeOS's `colors` take the same names
(see [§20](#20-doors-bbsdoor)).

---

## 15. FrameBuffer & ANSI text

`BBS::FrameBuffer` is the offscreen grid an Application draws into. Cells
hold `(char, sgr)` pairs; `diff` computes the minimal ANSI byte stream to
transform one frame into another (only changed cells get redrawn).

Direct API:

```ruby
fb = BBS::FrameBuffer.new(cols, rows)
fb.move(col, row)                              # 1-based
fb.write('Hello', sgr: "\e[1;33m")
fb.write_ansi("\e[1;33mbright\e[0m  normal")   # embedded SGR adds to base_sgr, a reset returns to it
fb.fill(x:, y:, width:, height:, sgr:, char: ' ')
fb.hline(x:, y:, length:, char: '─', sgr:)
fb.vline(x:, y:, length:, char: '│', sgr:)
fb.box(x:, y:, width:, height:, sgr:, fill_sgr:,
       style: :single|:double, title:, title_sgr:, title_indent:)
fb.shadow(x:, y:, width:, height:, sgr:)
fb.clip(x, y, width, height) { … }             # what the block writes outside the rectangle is dropped
delta = fb.diff(prev_fb)                       # ANSI byte stream
```

`clip` lets a view larger than its bounds draw itself shifted, a picture
scrolled to the part that is chosen, without spilling over its window's frame;
clips nest (the rectangles meet).

The one set of ANSI text helpers of rubbs (all built on `BBS::Ansi::CSI_RE`):

- `BBS::FrameBuffer.plain(text)` — the text without its escape sequences.
- `BBS::FrameBuffer.visible_width(text)` — length ignoring SGR escapes.
- `BBS::FrameBuffer.clip_ansi(text, max_width)` — truncate keeping styles intact.
- `BBS::FrameBuffer.wrap_ansi(text, width)` — word-wrap with SGR state
  carried across wrapped lines: the one word-wrap (`Petscii::Screen#wrap`,
  the dialogs and the Markdown renderer use it).

---

## 16. Markdown renderer

`BBS::Markdown.to_lines(text, width:, theme:)` → Array of ANSI strings,
one per terminal line. Feed it into a `BBS::Widgets::ScrollView` or an
`Info` window with `scroll: true`. In an Application `markdown(text, width)`
renders in its theme (a master/detail's `detail` block returns it); in a
`Petscii::Face` `markdown(text)` renders in the C64 colours, indented.

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

## 17. Banner & ERB screens

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
WELCOME = BBS::Flow.define(screens_dir: 'screens') { screen :welcome }

# screens/welcome.erb
<%= clr %><%= banner 'Welcome' %>
   <%= green %>Hello <%= @username %>!<%= reset %>
```

The ERB context exposes color helpers (`green`, `yellow`, `cyan`, `white`,
`gray`, `red`, `dim_green`, `clr`, `reset`) plus `banner(text, padding:)`
and `big_banner(text, font:)`. Instance variables are populated from
`vars` (resolved against `@ctx` if the value is a Symbol).

## 18. Persistence and shared blocks (`Model`, `Database`, `Store`, `Snapshot`, `HTTP`, `Cache`, `RateLimit`, `Text`, `Nodes`)

The parts every content board needs, so a board writes none of them by hand.

### `BBS::Model` and `BBS::Database`

Each table of a board has its model in `lib/domain/model`: a `BBS::Model`
(a `Sequel::Model`) whose class methods are the queries, so SQL lives
nowhere else. The database is bound when the board starts, so a model file
loads without a connection.

```ruby
# lib/domain/migrations.rb — the schema, one step per version (PRAGMA user_version)
MIGRATIONS = [
  'CREATE TABLE entries (id INTEGER PRIMARY KEY, name TEXT NOT NULL, text TEXT NOT NULL, written_at INTEGER NOT NULL)',
  'CREATE INDEX entries_by_name ON entries (name)',
  ->(db) { db[:entries].insert(name: 'sysop', text: 'Welcome', written_at: Time.now.to_i) }
].freeze

# lib/domain/model/entry_model.rb
class EntryModel < BBS::Model
  table :entries                                  # table :rfcs, database: :index for a second database

  def self.newest = reverse(:id).all
  def self.sign(name, text) = create(name: name, text: text, written_at: Time.now.to_i)
  def day = Time.at(written_at).strftime('%Y-%m-%d')
end

# lib/domain/sample_bbs.rb
class SampleBBS
  include BBS::Domain

  path     :db, 'data/sample.sqlite3'
  database :db, MIGRATIONS                         # opened at start, the models bound
end
```

```ruby
EntryModel.all
EntryModel.where(name: 'ada').reverse(:id).limit(10).all
EntryModel.group_and_count(:name).all
EntryModel[3]&.update(text: 'better')
EntryModel.db.fetch('SELECT … FROM fts WHERE fts MATCH ?', words).all   # plain SQL, in the model, where it is needed
```

Everything of `Sequel::Model` is there (datasets, associations, hooks,
validations). `BBS::Database.open(path, migrations)` opens a file in WAL mode
with foreign keys on and a busy timeout; the connection pool serves the
callers' threads. The migrations are counted in `PRAGMA user_version`, so a
database made with rubbs 2.2's `BBS::SQLite` goes on where it was. A step is
SQL (one or more statements) or a callable given the `Sequel::Database`.
In a test, `BBS::Test.database(MIGRATIONS)` is a fresh database with the
models bound to it.

`rake bbs:check` wants a model for every table (`models`) and SQL only in
`lib/domain/model` and `lib/domain/migrations.rb` (`raw_sql`). A board keeps
a repository only for what is not its database: HTTP, files, an archive.

### `BBS::Store`

A thread-safe, upsert-by-`session_id` table in an SQLite file (`BBS::Database`). Used by
`Flow#persist` but useful standalone.

```ruby
USERS = BBS::Store.new(
  path:    'data/users.csv',
  headers: %w[session_id timestamp username email]
)

USERS.upsert(session_id: sid, username: 'joe', email: 'j@e.com')
USERS.find(sid)        # => { 'session_id' => …, 'username' => 'joe', … } or nil
USERS.all              # => [ {…}, {…}, … ], oldest first
USERS.delete(sid)
```

- A `.csv` path means the `.sqlite3` file beside it (`data/users.sqlite3`).
  The CSV file of an earlier version is imported on first use, when the table
  is empty, in one transaction, and renamed to `users.csv.imported`.
  `USERS.open!` does it at once, at boot. A row that is not CSV, has more
  fields than the header or no `session_id` does not stop the import: it is
  skipped, written under the header to `users.csv.rejected` for the sysop,
  and counted in the log line.
- Headers `session_id` and `timestamp` are filled automatically when present;
  a header added later becomes a new column.
- Values are cleaned with `BBS::Text.clean`; `find` / `all` return Hashes.


### `BBS::Snapshot`

A catalog kept as one gzipped JSON file and held in memory whole: the seed
that ships with the board, the fresher copy a refresh writes into `data/`,
whichever is newer read at start, and a new one swapped in at once when a
refresh lands. The block turns the records (a Hash) into what the board
reads.

```ruby
CATALOG = BBS::Snapshot.new(seed: 'config/catalog.json.gz', path: 'data/catalog.json.gz',
                            source: 'Wikidata (CC0 1.0)') do |records|
  records['series'].map { |r| SeriesModel.from_record(r) }
end
CATALOG.value                                   # what the block made of the newest records
CATALOG.generated_at                            # when those were fetched
CATALOG.replace(fresh_records)                  # written to path, swapped in
CATALOG.refresh_every(3600, ttl: 7 * 86_400) { CatalogImport.fetch }
```

- A file that cannot be read is logged and passed over; with neither, the
  value is the block's of an empty Hash (`generated_at` is
  `BBS::Snapshot::NEVER`).
- `replace(records)` writes the file atomically (`Snapshot.write(path,
  records, at, source:)`, which a board's import tool uses for the seed)
  and raises when it cannot; the old value stays then.
- `refresh_every(every, ttl:) { … }` checks every `every` seconds in a
  `BBS.background` thread and fetches with the block when the records are
  older than `ttl`; a block that answers `nil` (or empty) or raises leaves
  the old records, and the error is logged. `age` is their age in seconds.

### `BBS::HTTP`

Bounded requests to the services a board shows. Every failure raises
`BBS::HTTP::Error`, whose message names the address without its query string;
a body over `max_bytes` raises its subclass `BBS::HTTP::TooLarge`, before a
byte is read when the `Content-Length` says so.

```ruby
response = BBS::HTTP.get('https://en.wikipedia.org/w/api.php?action=query&…',
                         headers: { 'Accept' => 'application/json' })
response.status    # => 200
response.ok?       # => true for 2xx; other statuses are returned, not raised
response.headers   # => { 'content-type' => … }   (lowercase names)
response.body      # => binary String

BBS::HTTP.post(SPARQL_URL, body: URI.encode_www_form(query: q),
               headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
```

| Option | Default | |
|---|---|---|
| `open_timeout` / `read_timeout` | 5 / 15 s | per connection / per read |
| `deadline` | 30 s | the whole request, redirects included |
| `max_bytes` | 4 MiB | the body is streamed and the request fails above it |
| `redirects` | 3 (`post`: 0) | followed to `http`/`https` only |
| `public_only` | `true` | refuses hosts that resolve to loopback, private, link-local, CGNAT, ULA and other non-public ranges (`BBS::Address.public?`); the vetted address is the one connected to, Host and SNI kept |
| `user_agent` | `BBS.config.user_agent` | |
| `to` | `nil` | an IO a 2xx body is written to as it comes (`body` is `nil` then), for a download too big for the memory; still capped by `max_bytes` |

```ruby
File.open(path, 'wb') { |file| BBS::HTTP.get(url, to: file, max_bytes: 64 * 1024 * 1024) }
```

### `BBS::Cache`

```ruby
ARTICLES = BBS::Cache.new(ttl: 600, max_entries: 500, max_bytes: 8 * 1024 * 1024)
ARTICLES.fetch([lang, title]) { BBS::HTTP.get(url).body }
```

TTL, least-recently-used eviction, a byte cap (`bytesize`, or `size: ->(v) { … }`),
one computation per key (callers missing the same key at once wait for it and
share its value or error), and the expired value served when the computation
raises. `delete(key)`, `clear`, `size`. `refresh(key) { … }` computes the
value anew and replaces the kept one only when the block succeeds, so a
background refresh never empties the cache:

```ruby
BBS.background('catalog', every: 3600) { CATALOG.refresh(:all) { repository.load } }
```

### `BBS::RateLimit`

```ruby
TIPS = BBS::RateLimit.new(limit: 3, per: 3600)
key  = session.caller_key                # caller_key in an Application or a Petscii::Face
TIPS.allow?(key)   # => true, and counted; false when over the limit
TIPS.wait(key)     # => seconds until the next event is allowed (0.0 now)
```

A sliding window per key, thread-safe; quiet keys are forgotten.
`BBS::RateLimit.caller_key(session)` (`session.caller_key`) is the caller's IP address on the internet, and
`line:<session id>` behind a local proxy (bbs-web), whose address is shared.

- Several limits at once (the caller's and the whole board's) are checked
  with `BBS::RateLimit.allow_all?([[PER_CALLER, key], [PER_BOARD, :all]])`: the
  event is counted in every limit or, when one has no room, in none.
- `room?(key)` checks and `record(key)` counts apart, for an event counted
  only when it went wrong:

  ```ruby
  return locked_out unless LOGINS.room?(key)
  LOGINS.record(key) unless password_ok?(name, password)
  ```

- With a `store:` (the board's `Sequel::Database`) the events are kept in its `rate_limit_events` table
  under the limit's name, so a lockout outlasts a restart:
  `BBS::RateLimit.new(limit: 10, per: 600, store: DB, name: 'logins')`.

### `BBS::MediaWiki`, `BBS::Wikipedia` and `BBS::Wikidata`

`BBS::MediaWiki` is the Action API of any MediaWiki site (Wikipedia, Memory
Alpha, any `api.php`) as a board asks it: through `BBS::HTTP`, with the
board's User-Agent (a wiki may answer 403 without one), paced so that all
callers together send at most `rate` requests a second (a request that would
wait more than `max_wait`, 3 s, for its turn is not sent). The answer comes
parsed; a failure raises `BBS::MediaWiki::Error`, a `BBS::HTTP::Error`, whose
message names the wiki.

```ruby
ALPHA = BBS::MediaWiki.new(endpoint: 'https://memory-alpha.fandom.com/api.php', name: 'Memory Alpha',
                           user_agent: 'Starbase BBS (+https://teletypegames.org)', rate: 3)
ALPHA.get(action: 'query', list: 'search', srsearch: 'tribbles')
```

`BBS::Wikipedia` is one, with the language in each call and one pace for all
languages; it raises `BBS::Wikipedia::Error` (a `BBS::MediaWiki::Error`).

```ruby
WIKIPEDIA = BBS::Wikipedia.new(user_agent: 'Alexandria BBS (+https://teletypegames.org)', rate: 5)
WIKIPEDIA.get('en', action: 'query', list: 'search', srsearch: 'Commodore 64')
# => { "query" => { "search" => [...] } }   (format=json, formatversion=2 added)
```

`BBS::MediaWiki::Extract.sections(title, extract, skip: Extract::SKIP)` cuts the
plain-text extract of an article (`prop=extracts`, `explaintext=1`,
`exsectionformat=wiki`) into `[heading, markdown]` pairs at its level-2
headings, ready for `BBS::Markdown`: the lead under `title`, deeper headings
as Markdown headings, formulas as readable text, and the sections named in
`skip` (lowercase; by default references, notes and links in English,
Hungarian and German) left out.

`BBS::Wikidata` is the SPARQL endpoint of Wikidata (CC0) for a catalog
import: `select(query)` posts the query (long timeouts, a 32 MB cap, a pause
before each) and returns the result rows; `BBS::Wikidata.qid(binding)` and
`BBS::Wikidata.text(binding)` read a row's values. A failure raises
`BBS::Wikidata::Error`, a `BBS::HTTP::Error`.

### Where an error is handled: repositories raise, services decide

A board's layers handle a failure of a service in one place:

- A **repository** (`lib/domain/repository`) talks to the outside world and
  lets its failures go up: `BBS::HTTP::Error` (and `BBS::Wikipedia::Error`, its
  subclass) as it comes, or a domain error of the board for what is wrong with
  the answer itself. It does not rescue them into `nil` or an empty list, and
  writes no text for the caller.
- A **service** decides what the caller sees: it rescues those errors,
  writes one `BBS.log` line, and returns what the UI shows (a cached answer, an
  empty result, a message of its own).
- The **UI** never rescues `BBS::HTTP::Error`; it shows what the service gave.

So an error message with a URL or a token never reaches a caller, and each
failure is logged once.

### `BBS::QR`

A QR code drawn in text, for a phone to read off the caller's screen: the
address of a story, a page to open in a browser. The code is encoded by the
`rqrcode_core` gem (the smallest version that holds the text, error
correction `:l`), and drawn white on black, two modules to a cell, so the
modules come out square on both kinds of screen:

- `BBS::QR.ansi(text, width: 80, height: 24)` — a modern terminal, whose cells
  are twice as tall as wide: half blocks (`▀ ▄ █`), two rows of modules a line.
- `BBS::QR.petscii(text, cols: 39, rows: 20)` — a Commodore 64, whose cells are
  square: quadrant blocks, two by two modules a cell; the quadrants the C64
  has no character for are the reverse of those it has. The defaults leave
  the last column free (a full row wraps) and five rows for a title and a
  prompt: up to a version 4 code (78 bytes), a 19×19-cell square.

Both return the lines with their colours as ANSI SGR (and reverse video),
which a PETSCII session turns into the C64's colour and RVS codes, so a line
is written as it is or goes into a window body. Two light modules of quiet
zone go around the code (`quiet:`). A text that does not fit the room
raises `BBS::QR::TooLong` (an `ArgumentError`): say so, and show the address
as text.

The faces draw one with a word, sized to the screen and with the
`TooLong` case handled:

```ruby
# A Petscii::Face (or a BBS::Petscii::Screen): centred, or an alert when it does not fit
title('SCAN THE LINK')
pause if qr(item.link)

# An Application: a window as big as the screen allows
qr item.link, title: 'Scan me'
```

Underneath:

```ruby
BBS::QR.petscii(item.link).each { |line| screen.puts(" #{line}") }
BBS::QR.ansi(item.link, width: 42, height: 20)   # lines for a window body
```

`BBS::QR.modules(text, level: :l, max_version: 40)` is the bare matrix, rows
of `true` for a dark module, for a drawing of a board's own.

### `BBS::Text` and `BBS::Address`

- `BBS::Text.clean(text, keep_newlines: true)`: valid UTF-8, without C0
  controls (tab kept, LF kept), DEL, C1 and the bidirectional
  override/isolate characters; with `keep_newlines: false` each line end
  becomes a space, so the words of two lines stay apart.
  `BBS::Text.line(text)` is one clean line: whitespace runs (line ends and
  tabs too) one space, no space at either end. `BBS::Text.printable?(char)` is
  the rule of every input (`Event#char?`, `TextBuffer`).
- `BBS::Address.local?(ip)` (private, loopback, link-local) and
  `BBS::Address.public?(ip)` (on the public internet).

The frame buffer stores no control character either, so text from a service
cannot move or restyle the caller's screen.

### `BBS::Nodes`

The node numbers of a board: each call gets the lowest number no other call
has, for the length of the call, the way a multi-line BBS showed "Node 2".
Thread-safe; one instance is shared by the calls it counts.

```ruby
NODES = BBS::Nodes.new
NODES.take { |node| run_call(node) }   # the number is free again when the block ends, however it ends
NODES.taken                            # => [1, 3], lowest first
```

---

## 19. AI characters (`BBS::AI`)

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
| `Client.new(url:, model: nil, api_key: nil, open_timeout: 2, read_timeout: 30, deadline: 120, max_bytes: 65_536)` | `#stream(messages, **options) { \|piece\| }` over `/v1/chat/completions` with `stream: true`; `#enabled?` is false for an empty URL. At most `BBS.config.ai_concurrency` requests run at once in the process; a request that waits 5 s for its turn raises `BBS::AI::Busy` (a `BBS::AI::Error`, as are a passed `deadline` and a reply over `max_bytes`) |
| `Chat.new(persona:, client:, history: 6, key: :ai_history, filter: PLAIN_TEXT, options: {})` | `#reply(text, ctx, facts: nil, fallback: nil) { \|piece\| }` returns the reply and yields it as it streams. The history lives in `ctx[key]`, so it lasts for the call. `facts` is added to the system prompt for this one request (what the character should know right now, looked up for the question; not kept in the history); `fallback` replaces the persona's canned reply when the model is missing or fails. `filter` drops markdown marks and emoji. `options` override the persona's. |
| `Typewriter.new(io, prefix:, style:, width: nil)` | `#write(piece)`, `#finish(newlines: 2)`: word-wraps streamed text to the caller's terminal under the prefix |

- With an empty URL, or when the request fails before any text arrived, the
  reply is the persona's canned one. A reply cut off mid-way is kept.
- A small model copies its examples far better than it follows the system
  prompt, and a long history makes it repeat its own slips: prefer more
  examples and a short `history`.

---

## 20. Doors (`BBS::Door`)

A door is a program the caller steps into from the BBS, as in the doors of the
old boards: the BBS hands the telnet line over, the program talks to the
caller directly, and the line comes back when the program exits. The program
is a `BBS::FakeOS` definition (see the comment in `bbs/fake_os.rb`), a
`BBS::Flow`, or anything that responds to `call(session, context)`.

```ruby
APP = BBS::Application.define do
  door :sermo, Sermo::OS, label: 'SERMO', hint: 'A machine that talks back'
  door :dice,  ->(session, ctx) { DiceGame.new(session).play }, label: 'Dice'

  command(:sermo, 'SERMO', key: 'F5') { open_door(:sermo) }
  menu 'Doors', :doors                          # one item per declared door
end

BBS.board 'Door BBS', DoorBBS do
  modern { ask :username, prompt: 'Name'; app APP }
end
```

- `open_door(:name)` ends the application with `:halt` and leaves the door in
  `context[:door]`. The application's run (`Builder#run`, what `BBS.board`
  and the `app` step call) then runs the door and builds the application
  again; a plain `APP.build(...).run` would only end.
- A `Petscii::Face` steps through a door with `open_door(door)`, a
  `BBS::Door` it holds: the line goes to the program and comes back to the
  face.
- `BBS::Door.new(name, program, label:, hint:, about:, petscii:)`: `label`
  is its menu item (default the name in capitals), `hint` a line for the
  statusbar while the item is highlighted, `about` a longer text for a list
  of doors, `petscii` the program a PETSCII line gets instead of `program`
  (a version drawn for 40 columns), `nil` for the same one.
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
- A FakeOS names its colours by role with `colors`: each a colour name or
  an xterm-256 index (`BBS::Style`, the text colour), a Hash of
  `BBS::Style[]` options or an SGR String:
  `colors text: :green, accent: :bright_green, dim: { fg: :green, faint: true }`.
- A FakeOS with a coloured screen sets `colors base:`: every reset returns to
  it and `cls` fills the screen with it, so a background survives the prompt,
  the caller's echo and new lines. Give each colour role the same background,
  since an SGR that starts with `0;` clears it.

### Telnet gateways (`BBS::Gateway`)

A door to another telnet board, the telnet gateway of the old BBSes: the line
goes on to that board as it is, and comes back when it hangs up. The other
board runs its own code on its own server; this one only carries the bytes.

```ruby
FEEDIA = BBS::Gateway.new(host: 'host.docker.internal', port: 2327, name: 'Feedia', public_only: false)
door :feedia, FEEDIA, label: '&Feedia'
```

- The host is resolved once (an IPv4 address when it has one) and the call
  goes to that address, which must be on the public internet
  (`BBS::Address.public?`) unless the gateway is made with
  `public_only: false`. So a listing that names `127.0.0.1`, a private or a
  link-local address cannot turn the board into a relay into its own network:
  the caller is told the board may not be called from here, and the Report's
  `error` is a `BBS::Gateway::Refused`. A board that dials its neighbours
  (`host.docker.internal`, another container) says `public_only: false`.

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
- `forward: true`, for a board of one's own only, says who is calling, as a
  proxy's `X-Forwarded-For` does in HTTP: before anything else the gateway
  sends the other board three telnet NEW-ENVIRON (RFC 1572) variables,
  `BBS_FACE` (`modern` or `petscii`, what the caller picked here; `modern` for
  a translated C64), `BBS_CLIENT_IP` (the caller's address) and `BBS_VIA`
  (`config.log_tag`). A rubbs board believes them only from a neighbour, a
  private or loopback address (`BBS::Address.local?`), and then
  `session.forwarded_face`, `session.caller_ip` and `session.via` answer from
  them: `BBS::Terminal` skips its question and splash, and
  `BBS::RateLimit.caller_key` counts the real address. From anywhere else they
  are kept (`session.telnet_env`) but not believed, and `caller_ip` is the
  line's own. Never forward to someone else's board: it would learn the
  caller's address.
- A directory that dials many boards makes a gateway a call
  (`connect_timeout:` sets the wait, 5 s by default) and reads how it went from
  the `BBS::Gateway::Report` its block gets: `connected`, the `error` that kept
  it from connecting (`SocketError` for a name that does not resolve,
  `BBS::Gateway::Refused` for an address that is not public,
  `Errno::ECONNREFUSED`, a timeout), the `address` called, `connect_seconds`,
  the bytes `received` from the other board and who `hung_up`. The block runs
  when the call is over, also when the caller hung up inside.

```ruby
BBS::Gateway.new(host: board.host, port: board.port, name: board.name, connect_timeout: 10).call(session) do |report|
  record(board, report.connected ? 'ok' : 'refused')
end
```

- A Commodore 64 can call a board made for ASCII and ANSI terminals with
  `translate: true`: the line then goes through a `BBS::Gateway::AsciiBridge`.
  The board's text (UTF-8, or CP437 once it is not UTF-8) reaches the C64 as
  PETSCII, with letters in the C64's case, ANSI colours as C64 colours and
  line drawing as the nearest glyph; the C64's keys reach the board as an ANSI
  terminal sends them (RETURN as CR, DEL as backspace, the cursor keys as
  `ESC [ A`…). The board sees an `ANSI` terminal of the C64's 40 columns. A
  modern caller's line is never translated.

```ruby
BBS::Gateway.new(host: board.host, port: board.port, translate: !board.petscii?).call(session)
```

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

### One call for either protocol (`BBS::Transfer`)

A file sent by the protocol the caller's terminal receives with, and what
to tell the caller before and after. XMODEM carries no file name, so the
terminal asks for one: `start` says which.

```ruby
protocol = :xmodem_1k                                  # a key of BBS::Transfer::PROTOCOLS
say(BBS::Transfer.start(protocol, 'GAME.PRG', data.bytesize))
result = BBS::Transfer.send(session, protocol, 'GAME.PRG', data)
say(BBS::Transfer.result(result, protocol, 'GAME.PRG'))
```

- `PROTOCOLS` is `{ zmodem: 'ZMODEM', xmodem_1k: 'XMODEM-1K', xmodem:
  'XMODEM' }`; `label(protocol)` is the name.
- `send(session, protocol, name, data)` returns `:ok`, `:cancelled` or
  `:timeout`, and raises `BBS::Hangup` when the line drops.
- `start(protocol, name, size, save_as: name)` is the sentence before the
  transfer (for XMODEM: start the download and save it as `save_as`);
  `result(result, protocol, name)` the one after it (for XMODEM: the file
  can be longer by up to a block).
- In an Application, run it inside `with_line`.

---

## 21. Telnet, sessions & input model

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
session.settle(timeout: 1.5) # wait for the telnet answers (NAWS), drop typeahead; self or nil
session.petscii!         # from here on the line speaks PETSCII to a C64
session.petscii?
session.caller_key       # the key the caller is known by for rate limits (BBS::RateLimit.caller_key)
session.hand_over { |s| … }  # lend the line: mouse off, screen cleared (modern), the mouse back after
```

`hand_over` is what an Application's `with_line` and a gateway or file
transfer use; it returns the block's value. `readkey` returns `nil` when
the caller has gone; the screens, faces and pages raise `BBS::Hangup` (an
`IOError`) for it, and the flow ends the call quietly.

Telnet options negotiated on connect: `SGA` (suppress go-ahead), `ECHO`
(server-side echo), `NAWS` (terminal size, clamped to 20–255 × 8–100). A line
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

Telnet commands are taken out of the byte stream by `BBS::Telnet::Parser`, a
small state machine (a doubled IAC is a data 255, a subnegotiation keeps at
most 64 bytes); the same parser reads both ways of a `BBS::Gateway`:

```ruby
parser = BBS::Telnet::Parser.new { |command, argument| … }   # WILL/WONT/DO/DONT + option, or SB + bytes
parser.parse(chunk)   # => the data bytes of chunk
parser.feed(byte)     # => byte, or nil when it belongs to a command
```

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

The editor can autosave, so a hang-up does not lose what was typed. It is off
unless asked for, and it knows nothing about where the text goes: with
`autosave:` seconds and a block, the block gets the text (lines joined by LF)
every that many seconds while it changes, whether the caller is typing or
thinking, and once more when the caller hangs up; never when it did not
change, and not on save or quit, which `run` returns anyway. An exception in
the block is logged and the editing goes on. The editor then reads the keys
with a timeout, so it keeps the session's idle limit itself and raises
`IO::TimeoutError` (an IOError) past it, as the line would.

```ruby
body = screen.edit(post.body, title: 'BODY', autosave: 15) { |text| drafts.save(draft_id, body: text) }
```

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
adds keys that return a value without an item. `fill: true` keeps the
`height:` rows when the items take fewer, so a full-screen menu keeps its
about and status rows at the bottom (a status row coloured
`colors: { hint: "#{CY}#{RV}" }` makes a footer bar). The roles and their
default colours are `BBS::Selector::COLORS` (the C64 palette); a
`BBS::Petscii::CanvasMenu` takes the same roles. The layout is a strategy:
`Selector::Columns` (one or more columns, pages) or `Selector::Row`
(`across: true`). It raises IOError
when the caller hangs up.

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

### The screen of a line-by-line board (`BBS::Petscii::Screen`)

What every line-by-line C64 board writes on: the 40×25 screen of one call
and the ways such a board talks. A `BBS::Petscii::Face`
([§7](#7-the-line-by-line-face-bbspetsciiface)) makes one per call and
answers its methods itself, so a face writes `title(…)`, `page(…)`,
`pick(…)` bare; a door or a tool can make one on a session. The colours are
two-letter ANSI constants in `BBS::Petscii::Colors` (`WH YE CY LG GR DG LB
BL GN RD PU OR`, `RV`/`RO` reverse on/off), which the PETSCII line turns
into the C64's own.

```ruby
screen = BBS::Petscii::Screen.new(session)
screen.title('the shelves', 'q: back')          # CLR + reversed title bar
screen.say('A paragraph, wrapped to 38 columns.', color: GR)
screen.page('chapter 1', lines, numbers: true)  # 20 lines a page, RETURN for more
book = screen.pick('the shelves', books, &:title)   # numbered BBS::Selector.list
key  = screen.actions(%w[r read], %w[q back])       # a row of keys, cursor menu
name = screen.ask(' name> ', max: 20)               # BBS::Field
text = screen.edit('', title: 'TIP', single_line: true, max: 200)   # BBS::Editor
screen.choose(' sure? (y/n) ', %w[y n], back: 'n')  # one key of a few, a prompt
screen.within('SCAN THE LINK') { screen.pause if screen.qr(url) }   # the title before it comes back
```

The screen's menus are `BBS::Selector` configurations: `pick` a numbered
list under a title, `menu` a selector at the cursor, `actions` a row of keys.
`choose` is the one key prompt (no menu: the keys typed after it). `pick`
takes `commands:` (`{ 's' => 'search' }`, the key returned) and
`item_commands:` (`{ 'd' => 'discard' }`, `[key, item]` returned for the lit
item); both are listed on the hint row. Underneath, `BBS::Selector.new` takes
`exits:` and `item_exits:` the same way. The colour of `say` and `rule` is a
keyword (`say(text, color: RD)`).

The short sentences (`BBS::Petscii::Screen::Helpers`): `alert(text)` (red,
then a pause), `notice(text)` (green, then a pause), `prompt(label, hint:,
text:, max:, mask:)` (a field after a white label and `>`; `nil` when
empty), `confirm?(question)`, `number(label, range)`, `each_pick(heading,
items, label:)`, `markdown(text, width:, indent:)` (in `Screen::MARKDOWN`'s
C64 colours), `qr(text)`, `rule_line`, `within(title, right) { … }` (the
previous title drawn again after the block). `key` raises `BBS::Hangup`
when the line drops.

A class that includes `BBS::Petscii::Colors` writes the colours bare; a
`Petscii::Face` subclass has them as constants. On a C64 the screen makes
titles, paragraphs and list labels `plain` (`BBS::Petscii.plain`:
typography and accents become ASCII, so a line wraps where it is counted).
`Screen.new(session, cols: 80, rows: 24)` serves a modern terminal too:
there it clears with ANSI and leaves the text alone.

### Block-font logos, goodbyes, Discord (`BBS::BlockFont`, `BBS::Goodbye`, `BBS::DiscordWebhook`)

```ruby
F = BBS::BlockFont
F.half_blocks('WARP')                                   # 3 rows of ▀▄█ for a modern face
F.half_blocks('TTG BBS', colors: [YE, OR, RD])           # each row in its colour
F.petscii('SCRIPTORIUM', colors: [WH, WH, YE, YE, CY], glyphs: F::NARROW_I, indent: 2)
F.rows('TTG WIKI', glyphs: F::WIDE_W)                    # the pixel rows, # and .
```

`BlockFont` is a 3×5 font (A–Z, 0–9, space and `. , ! ? - + : ' /`); `glyphs:`
lays other shapes over it. A `Petscii::Face` masthead takes it with `logo`.

The goodbye is the last screen of a call, and `BBS.board` shows it after
each face by itself: a board only says its note.

```ruby
BBS.board 'Feedia BBS', FeediaBBS do
  preset TTG::PRESET
  goodbye "The stories are their publishers'."   # goodbye false: the faces say their own
end
```

`BBS::Goodbye.show(session, note:)` (the `goodbye` step) picks the face of
the line. On a modern terminal (`Goodbye.modern`) it writes "Thanks for
calling" and the board's title, the note, "More of us:" and the preset's
`url`, the QR code of the preset's `qr`, and NO CARRIER, in one write; on a
C64 (`Goodbye.petscii`) a reversed bar, the note and the address, the QR
code in the middle, then `+++`, `ATH0` and NO CARRIER a moment apart. The
title comes from `BBS.config.title`, the address and the QR code from the
`BBS::Preset`; without a `url` there is no "More of us:", without a `qr` no
code, and a text that needs more than 15 lines goes without one. A face
that says goodbye its own way (`modern APP, goodbye: false`) can still call
the building blocks with its own words:

```ruby
BBS::Goodbye.petscii(screen, color: YE, note: 'Bye for now.') do |s|
  s.puts " #{GR}the wiki on the web:#{LG}"           # in place of the note and the address
end
```

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

### Graphics screens and art (`BBS::Petscii::Canvas`, `BBS::Art`, `BBS::Petscii::CanvasMenu`, `BBS::Widgets::Scene`, `BBS::Season`)

The pieces of a picture-led board (the TTG Clubhouse): drawings kept as
readable YAML, drawn in 256-colour ANSI on the modern face and as raw PETSCII
in the C64's uppercase/graphics set on the other; a cursor menu on the C64
picture; and the time of day and the season for choosing a picture's layers.

**`BBS::Petscii::Canvas`** is the C64 screen as 40×25 cells in the
uppercase/graphics set (the suits, balls, rounded corners, diagonals and
quarter blocks live there). It turns into raw PETSCII — the whole screen once
(`frame`), then only what changes (`span`, `patch`, `update`) — sent with
`session.write_raw`, past the session's lowercase encoder. Cells are drawn
from Unicode (`GLYPHS`, `GLYPHS_REVERSED`: `█ ▀ ▐ ◢ ◣` are reversed codes),
colours are codes (`Canvas::GREEN`) or names (`:light_blue`).

```ruby
C = BBS::Petscii::Canvas
canvas = C.new
canvas.text(0, 1, 'TTG CLUBHOUSE', :yellow)
canvas.text(2, 1, '╭──╮', :light_blue)
canvas.text(3, 1, '█▀▀█', :orange)                 # reversed glyphs work too
session.write_raw(canvas.frame)                    # the whole screen

before = canvas.dup
canvas.text(2, 2, '●', :red)
session.write_raw(canvas.update(before))           # a patch: only the cell that changed
```

`patch(positions)` steps the cursor from cell to nearest cell; `update`
takes the cheaper of that and a whole frame. Aim for about 1.2 KB a screen
and under 200 bytes an animation step. `feed(bytes)` plays PETSCII onto a
canvas the way the C64's screen editor prints it — for tests: what the caller
sees after your bytes.

With `charset: :lower` the canvas is in the lower/upper set, where text
keeps its case (the lines, the cross and the blocks are still there; the
glyphs the set changes are left out): a full screen of text, a page of a
`BBS::Pages` runner. `diff(before)` is the change for a screen of text: a
patch of the changed cells row by row, or the whole frame when that is
shorter, an empty String when nothing changed; cheaper than `update` when
blocks of text change (a list's lit row, a page turned).

```ruby
shown  = nil
canvas = BBS::Petscii::Canvas.new(charset: :lower)
canvas.text(3, 1, 'Global Discovery', :light_green)
session.write_raw(shown ? canvas.diff(shown) : canvas.frame)
shown = canvas
```

**`BBS::Art`** loads a drawing from YAML. `chars` is the picture, `colors`
a palette letter a cell (`.` = none), `reverse` optional `R`s, `background`
optional (cp437 only: the second colour of a half block), `hotspots` the cells
the board fills from its data, `layers` the files stacked on it (snow,
pumpkin…). Every row is exactly `size[0]` wide; write the grids with `|2` so
a row that starts with spaces keeps them. A PETSCII art for the C64:

```yaml
# art/house.yml
size: [20, 6]
charset: petscii-upper     # only glyphs the uppercase set shows
palette:                   # C64 colour names, 256-colour indexes or '#rrggbb'
  y: yellow
  r: red
  b: brown
  g: dark grey
  w: white
chars: |2
       ◢████◣    ●    
      ◢██████◣        
      │ ▒  ▒ │        
      │ ▒  █ │  TTG   
  ▁▁▁▁│▁▁▁▁█▁│▁▁▁▁▁▁▁ 
                      
colors: |2
  .....rrrrrr....y....
  ....rrrrrrrr........
  ....b.y..y.b........
  ....b.y..b.b..www...
  ggggbggggbgbggggggg.
  ....................
hotspots:
  window_1: [6, 2]         # [col, row], 0-based
  window_2: [9, 2]
  sign: [14, 3, 3, 1]      # [col, row, width, height]
layers: [snow]             # art/snow.yml
```

```yaml
# art/snow.yml: a layer; spaces are transparent, 'at' places it
size: [10, 1]
at: [4, 0]
palette:
  w: white
chars: |2
   ▄▄▄▄▄▄   
colors: |2
  .wwwwww...
```

And a cp437 sign for the modern face, with backgrounds:

```yaml
size: [24, 4]
charset: cp437
palette: { y: yellow, o: 208, n: '#203060', w: white }
chars: |2
  ╔══════════════════════╗
  ║ ▄▀▀▄ TTG CLUBHOUSE ☼ ║
  ║ ▀▄▄▀  open tonight   ║
  ╚══════════════════════╝
colors: |2
  oooooooooooooooooooooooo
  oyyyyywwwwwwwwwwwwwwwyyo
  oyyyyyyyyyyyyyyyyyyyyyyo
  oooooooooooooooooooooooo
background: |2
  ........................
  .nnnnnnnnnnnnnnnnnnnnnn.
  .nnnnnnnnnnnnnnnnnnnnnn.
  ........................
hotspots:
  tonight: [8, 2, 13, 1]
```

```ruby
house = BBS::Art.load('art/house.yml').with(*BBS::Season.now.layers)  # only the layers it lists
session.write(house.ansi)                        # modern: 256-colour ANSI lines
house.draw(frame, x: 1, y: 2)                    # … or into a BBS::FrameBuffer
session.write_raw(house.petscii)                 # C64: a whole frame
house.draw_canvas(canvas, row: 1, col: 10)       # … or onto a canvas
house.hotspot(:window_1)                         # => Art::Hotspot col=6 row=2 …
```

A mistake raises `BBS::Art::Error` with the file, the grid, the row and the
column: a row of the wrong width, a letter not in the palette, a glyph the
charset cannot show (`Canvas.glyph?` for PETSCII, code page 437 for cp437), a
hotspot outside the art.

**`BBS::Petscii::CanvasMenu`** is `BBS::Selector` on a canvas: the same items
and keys (CRSR, RETURN, an item's key, RUN/STOP or ← to go back, numbers,
columns, pages, the about and hint rows), drawn in the uppercase set with the
lit item a reversed bar in its own colour; each move goes out as a patch of
the cells that changed (about 140 bytes for a 16-item, two-column menu).

```ruby
S = BBS::Selector
items = [S.item('CORK BOARD', key: 'm', value: :boards, color: :light_blue, about: 'READ AND POST'),
         S.item('GAMES ROOM', key: 'r', value: :doors, color: :orange),
         S.item('LEAVE',      key: 'q', value: :quit)]
menu = BBS::Petscii::CanvasMenu.new(session, items, canvas: canvas, row: 12, col: 1, width: 36,
                                    columns: 2, hint: 'CRSR: CHOOSE  RETURN: OPEN', idle: 0.5) do
  smoke.step(canvas)                 # bytes for an animation step while the caller thinks
end
menu.paint
session.write_raw(canvas.frame)      # the picture with the menu on it
choice = menu.run(drawn: true)       # without drawn: it paints and sends its rows itself
```

**`BBS::Widgets::Scene`** is an Art as a widget of the modern face: the art,
then each hotspot filled by its block at every render (a String with ANSI
colours, lines for a taller hotspot, or nil to leave the art). On a terminal
smaller than the art it is cut to its bounds; `crop: false` draws nothing
instead, `fits?` tells.

```ruby
scene = BBS::Widgets::Scene.new(art: house, align: :center)
scene.fill(:window_1) { node_busy?(1) ? "\e[38;5;220m▓" : nil }
scene.fill(:sign)     { |spot| "\e[1;37m#{inside_count}".ljust(spot.width) }
```

**`BBS::Season.now(tz: 'Europe/Budapest', at: Time.now, jam: nil)`** is the
time of day (`:dawn`, `:day`, `:dusk`, `:night`, by the sun at `latitude:` /
`longitude:`, Budapest by default) and the layers in effect: `:snow`
(December–February), `:pumpkin` (24–31 October), `:fireworks` (31 December
and New Year's Day until 06:00), `:bunting` (the days of `jam:`, a Range of
Date). It is pure: pass `at:` in tests. EU time zones and fixed offsets
(`'+01:00'`) work without gems; other IANA names need `tzinfo`.

```ruby
s = BBS::Season.now(jam: Date.new(2027, 1, 8)..Date.new(2027, 1, 10))
s.time_of_day          # => :night
s.layers               # => [:snow]
art = BBS::Art.load("art/house_#{s.night? ? 'night' : 'day'}.yml").with(*s.layers)
```

**`art-preview`** (an executable of the gem; `bin/art-preview` in a checkout)
checks a drawing and shows it while it is drawn:

```
art-preview art/house.yml                   # ANSI here, then size, palette, hotspots, PETSCII bytes
art-preview art/house.yml -l snow -s        # a layer stacked, the hotspots marked
art-preview art/house.yml --hex             # the PETSCII frame as a hex dump
art-preview art/house.yml --petscii h.seq   # the raw frame, e.g. for a C64 terminal program
art-preview art/house.yml --png h.png       # a C64 screenshot of the frame (VICE's character ROM)
```

`--png` plays the frame onto a canvas and draws it with the C64 character
ROM VICE installs (or `--chargen FILE` / `$C64_CHARGEN`); the ROM is not
shipped with the gem.

### Two faces on one port (`BBS::Terminal`)

A board with a modern face and a PETSCII face (a C64) asks the caller first, with the
guess above as the default:

```
TTG WIKI

1 - MODERN (ANSI/XTERM, 256 COLORS)
2 - COMMODORE 64 (PETSCII, 40 COLUMNS)

YOUR TERMINAL [1]:
```

`BBS.board` builds it when a board declares both faces:

```ruby
BBS.board 'TTG Wiki', WikiBBS do
  preset  TTG::PRESET          # its splash comes after the question
  modern  UI::Modern::APP
  petscii UI::Petscii
end
```

Inside, `BBS.board` calls `BBS::Terminal.flow(title:, modern:, petscii:,
splash:)` with the board's title, the two faces' flows and the preset's
splash, and keeps `mouse_on_connect` off: the mouse's escape sequence would
be garbage on a C64. The terminal flow asks, switches the line (`petscii!`
on a C64, `enable_mouse` on a modern terminal when `config.mouse` is on) and
runs that face's flow. The question is plain ASCII capitals, which both
machines print alike. A key (`1`/`M`, `2`/`C`/`P`) only picks and RETURN
takes it, so the RETURN of a line-mode telnet does not reach the first
screen; no answer in 60 s takes the pick or the guess.

The preset's `splash` is a `BBS::Splash`, a screen between the question and
the face: the board's two drawings (`BBS::Art`, the C64 one
`petscii-upper`), centred, with a prompt under them (PRESS ANY KEY TO
CONTINUE by default). Any key, or 60 s, goes on; a modern window narrower
than the drawing skips it.

```ruby
SPLASH = BBS::Splash.new(modern: BBS::Art.load('art/logo-modern.yml'),
                         petscii: BBS::Art.load('art/logo-c64.yml'))
MY_PRESET = BBS::Preset.new(splash: SPLASH, url: 'example.org')
```

The TTG boards take theirs from `ttg-common` (`TTG::PRESET`).

A call that comes through another rubbs board's gateway with `forward: true`
had its question there: the terminal flow takes the face picked there
(`session.forwarded_face`) and shows neither the question nor the splash.

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

### The rake tasks of a board and its shape (`bbs/rake`, `BBS::Check`)

```ruby
# Rakefile
require 'bbs/rake'
BBS::Rake.board                 # BBS::Rake.board(faces: false) for a board without lib/ui faces
```

| Task | What it does |
|---|---|
| `rake test` | The tests: `test/**/*_test.rb`, with `test` and `lib` on the load path. |
| `rake bbs:check` | The board's shape (`BBS::Check`); fails with the list of what is out of it. |
| `rake` | Both: what CI runs. |

`BBS::Check` runs rules over the board's files. rubbs' own rules:

| Rule | Wants |
|---|---|
| `layout` | `bbs.rb`, `Rakefile`, `Gemfile(.lock)`, `README.md`, `lib/domain.rb`, `lib/domain/{model,repository,service}/`, a `test_helper.rb` |
| `bbs_rb` | `bbs.rb` is requires and one `BBS.board` declaration |
| `domain` | a class in `lib/domain/` that includes `BBS::Domain`; no `ENV` under `lib/ui` |
| `names` | each file of a domain layer defines the class of its name |
| `faces` | `lib/ui/modern.rb` and `lib/ui/petscii.rb` (unless `faces: false`) |
| `wording` | the faces' text table is `lib/ui/wording.rb` |
| `tests` | tests are `*_test.rb` and load the test helper |
| `old_forms` | none of the 1.x forms (`BBS.configure`, `Terminal.flow`, `ctx[:app]`, `status_hint`, `with_loading`, padded titles …) |

A family of boards adds its house rules with `BBS::Check.rule(:name, 'what it wants') { |board| board.fail(path, message) unless … }`
(the `Board` has `file?`, `dir?`, `read`, `glob`, `ruby_files`, `declaration`, `slug`, `env_prefix`);
ttg-common's are loaded with `require 'ttg/rake'`. A board turns a rule off with
`BBS::Rake.board(skip: [:name])`. `BBS::Domain` classes answer `environment_variables`, the
full names their settings read, for a rule that checks they are documented.

### Testing a board (`bbs/test`)

`require 'bbs/test'` (not loaded by `require 'bbs'`) gives a board's tests
`BBS::Test::Session`: a caller's line without a socket. The keys it will
press go in, what the board writes is kept, and it answers what a page, a
screen, a face or a flow asks of a `BBS::Session`.

```ruby
require 'bbs/test'

session = BBS::Test::Session.new(keys: [:down, :enter, 'q'])
BBS::Pages.new(session).run(Home.new)
assert_includes session.output, 'Global Discovery'

c64 = BBS::Test::Session.new(petscii: true)    # 40×25, PETSCII mode
c64.keys << 's'                                # a key for later
assert_raises(BBS::Hangup) { UI::Petscii.new(c64, {}, board).run }   # the keys ran out
c64.take                                       # the bytes written since the last take
```

- `keys` are Strings and Symbols as `readkey` returns them (`:idle` too);
  when they run out, `readkey` returns `nil`, a hang-up, so a face or a
  page ends with `BBS::Hangup`. `readline` joins the keys up to an `:enter`.
- `output` is everything written as one UTF-8 String, `raw` the bytes,
  `writes` each write, `last` the last one, `take` what came since the last
  `take`.
- `new(keys:, petscii:, cols: 80, rows: 24, session_id: 'test')`;
  `petscii!`, `caller_key` (`line:test`), `hand_over`, `enable_mouse` /
  `mouse_on?`, `idle_seconds` behave as on a real line; `line` is `nil`, so
  a gateway cannot be tested through it.

---

## 22. Source layout

| File | Responsibility |
|---|---|
| `lib/bbs.rb` | Public surface: `BBS.board`, `BBS.configure`, `BBS.config`, `BBS.start`, `BBS.log`, `BBS.background`. |
| `bbs/board.rb` | `BBS.board` and `BBS::BoardDefinition`: the board declared, configured and started. |
| `bbs/domain.rb` | `BBS::Domain`: settings, paths, services and background work of the board's domain object. |
| `bbs/preset.rb` | `BBS::Preset`: splash, goodbye address and QR code, User-Agent of a family of boards. |
| `bbs/hangup.rb` | `BBS::Hangup`, `BBS::LINE_DROPPED`, `BBS::Abort`. |
| `bbs/test.rb` | `BBS::Test::Session` for a board's tests (`require 'bbs/test'`). |
| `bbs/server.rb` | TCP accept loop, one thread per client, on-session-end hook. |
| `bbs/session.rb` | Telnet negotiation, mouse enable/disable, idle timer. |
| `bbs/telnet.rb`, `bbs/telnet/` | Telnet line I/O: `Codes`, the IAC `Parser`, `Keys` and `Escapes` (key parsing), `Mouse` (xterm SGR), `LineInput` (readline), PETSCII mode. |
| `bbs/petscii.rb`, `bbs/petscii/encoder*` | PETSCII: the C64's codes, the one glyph table (`GRAPHICS`, `ROUNDED_CORNERS`, `LOOK_ALIKES`), the C64's keys (`KEYS`), and the UTF-8/ANSI → PETSCII encoder. |
| `bbs/petscii/colors.rb`, `bbs/petscii/screen*` | The C64 names of the palette and the 40×25 screen of a line-by-line C64 board, with its helpers. |
| `bbs/petscii/face.rb`, `bbs/petscii/face/` | `BBS::Petscii::Face`: the line-by-line face declared (title, `Masthead`, `MainMenu`). |
| `bbs/pages.rb`, `bbs/pages/`, `bbs/page.rb` | `BBS::Pages` and `BBS::Page`: the full-screen page app for both faces (key map, painting, waiting, line input). |
| `bbs/paint.rb`, `bbs/style.rb` | Colours by role on both faces; SGR styles by colour. |
| `bbs/petscii/canvas.rb`, `bbs/petscii/canvas_menu.rb` | The C64 screen as cells in the graphics set (raw PETSCII, patches) and a `Selector` drawn on it. |
| `bbs/art.rb`, `bbs/widgets/scene.rb` | YAML drawings (ANSI and PETSCII, layers, hotspots) and the art as a modern-face widget. |
| `bbs/season.rb` | Time of day, season and holiday layers. |
| `bin/art-preview` | Checks and shows an art: ANSI, PETSCII bytes, a C64 PNG. |
| `bbs/block_font.rb` | A 3×5 block font for logos: half blocks (modern) and reversed spaces (C64). |
| `bbs/goodbye.rb` | The NO CARRIER screen of a call, modern and C64 (`Goodbye.show`). |
| `bbs/discord_webhook.rb` | Discord webhook posts, standalone: background thread, mentions off, relay limit. |
| `bbs/terminal.rb` | The terminal question of a two-faced board: modern (ANSI) or C64 (PETSCII). |
| `bbs/config.rb` | `BBS::Config` value object. |
| `bbs/flow.rb`, `bbs/flow/`, `bbs/flow_runner.rb` | Flow DSL, its steps (`call`, `app`, `face`, `goodbye`, …), the runner. |
| `bbs/selector.rb`, `bbs/selector/` | The cursor menu of a line-by-line board: layouts, cells, keys. |
| `bbs/frame_buffer.rb`, `bbs/frame_buffer/` | Double-buffer, delta diff, drawing helpers, the ANSI text tools (the one wrap). |
| `bbs/application.rb`, `bbs/application/` | The windowed face: the `Builder` DSL, `Command`, the bars, the desktop builder, the conveniences, window stack, event loop. |
| `bbs/part.rb` | `BBS::Part`: a piece of an Application declaration in a file of its own. |
| `bbs/widget.rb`, `bbs/container.rb` | Widget tree base. |
| `bbs/widgets.rb`, `bbs/widgets/` | Built-in widgets, one a file (Label, Button, TextInput, TextArea, Checkbox, ListBox, ScrollView, Scene, Desktop). |
| `bbs/window.rb`, `bbs/window_spec.rb`, `bbs/window_spec/`, `bbs/window_context.rb` | `Window` + the declared windows and the context their blocks run in. |
| `bbs/windows/reader.rb` | A long text to page through, with a position line and buttons. |
| `bbs/windows/info.rb` | Centered info / message / kv / scroll dialog. |
| `bbs/windows/form.rb` | Multi-field form with status line. |
| `bbs/windows/master_detail.rb` | Two-pane list / detail browser. |
| `bbs/windows/stream.rb` | Live log / chat window with input + polling. |
| `bbs/windows/button_bar.rb` | Bottom-row button layout helper. |
| `bbs/menu.rb`, `bbs/statusbar.rb`, `bbs/dialogs.rb` | Chrome + ad-hoc dialogs. |
| `bbs/focus_manager.rb` | Tab/Shift-Tab focus traversal. |
| `bbs/theme.rb`, `bbs/theme/presets.rb` | Theme roles and the presets as data (synchronet, nortoncommander, dosnavigator, neumanntronics, mono). |
| `bbs/ansi.rb` | The ANSI sequences and the one palette. |
| `bbs/markdown.rb` | Markdown → ANSI line array renderer. |
| `bbs/event.rb` | Unified key + mouse event objects. |
| `bbs/store.rb`, `bbs/store/csv_import.rb` | Thread-safe upsert-by-session table on SQLite (imports the CSV file of earlier versions, broken rows set aside). |
| `bbs/database.rb`, `bbs/model.rb` | A board's SQLite through Sequel (WAL, `user_version` migrations) and the model of each table. |
| `bbs/snapshot.rb` | A catalog as one gzipped JSON file in memory: seed, refresh, swap. |
| `bbs/nodes.rb` | Node numbers of the calls. |
| `bbs/http.rb` | Bounded HTTP GET/POST: deadline, body cap, safe redirects, public addresses only. |
| `bbs/cache.rb` | TTL + LRU + byte-capped cache with single-flight and stale-on-error. |
| `bbs/rate_limit.rb` | Sliding-window rate limit per key, several at once, in memory or SQLite; `caller_key(session)`. |
| `bbs/media_wiki.rb`, `bbs/media_wiki/extract.rb`, `bbs/wikipedia.rb` | the Action API of a MediaWiki site, paced, parsed; Wikipedia as one; extracts cut into sections. |
| `bbs/wikidata.rb` | Wikidata's SPARQL endpoint for catalog imports. |
| `bbs/qr.rb` | QR codes in half blocks (ANSI) and quadrant blocks (PETSCII). |
| `bbs/background.rb` | `BBS.background`: work in a thread with log and retry. |
| `bbs/text.rb`, `bbs/address.rb` | Control-free text; local / public IP addresses. |
| `bbs/fake_os.rb` | Character-mode OS simulator: boot script + command shell. |
| `bbs/door.rb` | Doors: hand the line to a program and take it back. |
| `bbs/gateway.rb`, `bbs/gateway/` | Telnet gateway doors: the line handed on to another board (`Link`, `Negotiation`, `AsciiBridge`), public addresses only by default. |
| `bbs/zmodem.rb`, `bbs/zmodem/` | ZMODEM send: file downloads to the caller's terminal (`Frames`, `Input`, `Output`, `Stream`, `Sender`). |
| `bbs/xmodem.rb` | XMODEM / XMODEM-CRC / XMODEM-1K send: file downloads for a Commodore 64. |
| `bbs/transfer.rb` | One call for either protocol, and what to tell the caller. |
| `bbs/ai.rb` | AI characters: persona file, OpenAI-compatible streaming client, chat with memory and fallback, typewriter output. |
| `bbs/banner.rb`, `bbs/renderer.rb` | FIGlet + ERB. |
| `test/` | minitest suite: `bundle exec rake test`; style: `bundle exec rubocop`. |
