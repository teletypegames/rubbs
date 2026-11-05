# rubbs 2.10

`BBS::Auth::Profile.extra(key, label, hotkey:, if:) { |session| … }`: a board adds its own places to the
profile's menu, above Back (`Profile.extras`, `Profile.clear_extras`). Nothing to change in a board.

# rubbs 2.9

For a sysop's screen: `BBS.calls` (the calls on the line, `BBS::Server#live` of `BBS::Server.current`),
`BBS::Session#started_at`, `#place` (the section opened last, or `› Name` inside a gateway) and
`#hang_up` (ends a call from another thread); `BBS::Log.recent` (the last 500 log lines as
`BBS::Log::Entry`). The home of the accounts lists and bans them (`Directory::Sysop`: `accounts`,
`entry`, `ban`, `unban`); a banned account's login is `:banned` (*This account is closed.*), through
the API too.

The accounts database gets its second migration (`banned_at`, `banned_by`, `ban_reason`), run by the
home board at its next start. Nothing to change in a board.

# rubbs 2.8.1

The `call ended` line kept `ip` and `via` only while the line was open, so it was written with no address and
every call came out `local`: a session now notes its address when the call comes in
(`Telnet::Forwarded#peer_ip`). Nothing to change in a board.

# rubbs 2.8

Log lines for a log pipeline to count callers and what they do (README, *Logging*): every line in a
call carries `ip` next to `session` (`BBS::Log.with_session(id, caller: session)`); `call ended` also
tells `via`, `face`, `cols`, `rows`, `naws` and `user`; new lines `use` (an Application command, a
PETSCII menu item), `door crossed` (a door or a gateway), `transfer` (a download), `rate limit refused`;
the `server` start line carries `rubbs` (`BBS.version`). `BBS::Session#face` and `#call_via`,
`BBS::RateLimit#name`, `BBS::Terminal.only`.

The lines of `BBS::DiscordWebhook` have the tag `discord` (msg `sent`, `failed`, `limited`) and the
webhook's `label` as a field; before, the label was the tag and only failures were logged. A log query
that looked for the label as the tag looks for `tag="discord"` and `label` now. Nothing to change in a
board.

# rubbs 2.7

The splash of a board with a login asks a caller who is not logged in: `Login | Register | Guest`
(white words, each key — L, R, G — green). L and R open the caller's profile
(`BBS::Auth::Profile.run(session, start: :log_in / :register)`), G or the wait running out goes on
as a guest. A call handed on from another board skips the splash, so it is asked once. `Splash.new(…,
choices: nil)` keeps the plain prompt; `colors:` changes the words' and keys' colours. Nothing to
change in a board.

# rubbs 2.6

The caller's profile on either face: `BBS::Auth::Profile` — the preset's drawing in the middle,
the title, who is on the line, and a cursor menu (log in, a new account, the password, log out,
back). A board opens it with `open_profile` (a `Petscii::Face`, an Application) or the built-in
`:profile` command; how it looks comes from the preset: `BBS::Preset.new(profile:
BBS::Auth::Profile::Look.new(modern:, petscii:, title:, note:, words:, colors:, c64:))`, and
without one it is plain. `BBS::Selector` takes `indent:` (columns of air on its left).

# rubbs 2.5.1

Auth events for a log pipeline: every login, failed login, lockout, registration, password change, role
change, logout and a caller handed on with a key (or refused) is one `auth` line with `event` and `asker`
(the board the caller is on; for the API, the board that asked), from `BBS::Auth.event`. The old
`login: wrong name or password` line is now `event=login_failed`. `BBS::Auth::Directory#statistics`
gives the accounts in numbers. Nothing to change in a board.

# rubbs 2.5

Accounts, roles and a login for a network of boards: `BBS::Auth`. Nothing a
board wrote changes; a board that wants it adds:

- `auth directory, login: :call | :menu | :both, guests: true` in `BBS.board` (README:
  "Accounts and login"); the home of the accounts declares
  `database :accounts_db, BBS::Auth::MIGRATIONS, name: :auth` and a `BBS::Auth::Directory`,
  and starts a `BBS::Auth::API`; the others use a `BBS::Auth::Remote`.
- `RUBBS_AUTH_SECRET` in every board's environment (the same, 32+ random bytes).
- In the faces: `identity`, `signed_in?`, `role?`, `log_in`, `log_out`; `command …, role:`;
  the built-in `:log_in` and `:log_out` commands for a menu.
- A board's own accounts move with `Directory#import` (a hex digest with
  `BBS::Auth::Password.from_hex`); its `context[:username]` / `context[:user]` become
  `identity`.
- A forwarding `Gateway` hands a signed-in caller on (`RUBBS_AUTH_KEY`); `audience:` names
  the board it dials when its `name:` is not that board's title.
- New gem dependency: `webrick`. A telnet subnegotiation may now be 640 bytes (was 64).

# rubbs 2.4

Running in production: a server that stops in order, a health probe and log
lines a pipeline can read. Nothing a board wrote changes; what it may add:

- **Stopping.** SIGTERM / Ctrl-C closes the port, tells the callers
  (`BBS_SHUTDOWN_SECONDS`, default 8, and `config.shutdown_notice`), waits for
  them, hangs up on the rest, then runs `on_stop { |board| … }` and the
  domain's new `stop` (background work stopped, databases closed). A domain that
  writes a file on a timer flushes it in `def stop; …; super; end`. Raise
  `BBS_SHUTDOWN_SECONDS` together with the supervisor's stop timeout
  (`stop_grace_period`).
- **Health.** `BBS::Health` answers `BBS-HEALTH` from loopback on the telnet port
  (`OK n/max` or `FAIL …`); `bbs-health` asks it. The domain's `health` (default:
  every database answers) says what is wrong; `def health = super + […]` adds more.
- **Logs.** `BBS.log(tag, message, level:, **fields)`; `BBS_LOG_FORMAT=json` writes
  JSON lines with the call's `session`. The server logs every call's end
  (`call: ended seconds=… end=hung_up|dropped|error|stopped`) and its own start and
  stop; the `Server stopped.` and `BBS listening on port …` lines of stdout are
  gone. Pass the exception itself to `BBS.log` (it adds the class, the message and,
  at `:error`, the backtrace) instead of formatting `"#{e.class}: #{e.message}"`.
- `BBS::Test::Session` takes a callable among its keys (called with the session
  when its turn comes) and has `announce`.

# rubbs 2.3

A model for every table: `BBS::Model` (a `Sequel::Model`) with the queries as
its class methods, the board's databases declared in its domain
(`database :db, MIGRATIONS`) and bound at start. `BBS::SQLite` and the
domain's `database(path, *steps)` instance method are gone; the migrations are
still counted in `PRAGMA user_version`, so the databases go on where they were.

- `MIGRATIONS` (the old `Repository::MIGRATIONS` steps) go to `lib/domain/migrations.rb`; a
  step that was a lambda gets the `Sequel::Database` now.
- Each `CREATE TABLE` gets `class XModel < BBS::Model; table :x; end` in `lib/domain/model`;
  the SQL of a table repository becomes class methods of its model, and the repository goes
  (a repository stays for HTTP, files, an archive).
- `db.query(sql, *args)` → `Model.where(…)` / `.all` / `.db.fetch(sql, *args).all` (rows have
  Symbol keys); `db.insert` → `Model.create(…)` / `.insert`; `db.change` → `.where(…).update/delete`;
  `db.get(...)['n']` → `.count`; `db.transaction` → `Model.db.transaction`.
- `BBS::RateLimit.new(store: db)` takes the `Sequel::Database` (`databases[:main]`).
- Tests: `BBS::Test.database(MIGRATIONS)` in place of a temporary `BBS::SQLite`.
- `rake bbs:check` wants a model for each table and SQL only in the model layer.

# rubbs 2.2

A board's rake tasks and a check of its shape: `require 'bbs/rake'` and
`BBS::Rake.board` in the Rakefile give `rake test`, `rake bbs:check` (`BBS::Check`:
files, names, the `bbs.rb` declaration, the domain, no 1.x forms) and `rake` (both, what
CI runs). House rules join with `BBS::Check.rule`; `Domain.environment_variables` lists
what a domain reads. Nothing changes for a board that does not use it.

# rubbs 2.1

2.1 adds to the DSL; nothing of 2.0 changes, except where the empty line
above a main menu goes when the menu has `above:` lines (now before them,
as boards had it on 1.x; `gap: :after` gives the 2.0 order).

- `main_menu(gap: :before | :after | false)`: where the empty line above the menu goes.
- `sub_menu(:name, title:, right:) { item …; back 'to the main menu' }` on a face, run with
  `sub_menu(:name)`; each menu keeps its own cursor (`face.cursors`).
- `each_pick(heading, -> { wall.all }, …)`: a callable list is read again each round.
- `goodbye(greeting: 'Thanks for reading')` (both faces), and a goodbye block gets the
  session too: `goodbye { |context, session| … }`.
- The call's context starts with `:started_at`; `BBS.duration(context[:started_at])` is
  `45s`, `12m` or `2h 5m`.

# Upgrading to rubbs 2.0

2.0 makes rubbs a DSL: a board's code says what the board *is* (its name,
its domain, its commands, menus, windows and screens) and rubbs does the
wiring. A board on 1.x has glue in every file; on 2.0 most of it goes.
`bbs/alexandria-bbs` is the reference: read its `bbs.rb`, `lib/domain/alexandria_bbs.rb`,
`lib/ui/modern.rb`, `lib/ui/modern/*` and `lib/ui/petscii.rb` side by side
with their 1.x versions (`git log -p`).

Nothing of 1.x stays as a second way: the old forms raise `NoMethodError` or
`ArgumentError`. The greps below find them; run them from the board's root:

```sh
grep -rnE '<pattern>' bbs.rb lib test
```

## 1. `bbs.rb`: `BBS.board`

```ruby
# 1.x
bbs = FeediaBBS.new
BBS.configure do |config|
  config.log_tag          = 'feedia-bbs'
  config.mouse            = true
  config.mouse_on_connect = false
  config.idle_seconds     = 600
  config.flow = BBS::Terminal.flow(title: 'Feedia BBS', modern: UI::Modern.flow(bbs),
                                   petscii: UI::Petscii.flow(bbs), splash: TTG::Logo.splash)
end
bbs.start
BBS.start

# 2.0
BBS.board 'Feedia BBS', FeediaBBS do
  preset  TTG::PRESET                    # splash, goodbye address + QR, User-Agent (ttg-common)
  modern  UI::Modern::APP                # an Application definition …
  petscii UI::Petscii                    # … or a BBS::Petscii::Face subclass, a Flow, or a block
  goodbye "The stories are their publishers'."
  idle 900                               # default 600
  mouse false                            # default true on the modern face
  on_start { |bbs| Web::Api.new(bbs).start }       # once at boot
  on_session_end { |session, bbs| bbs.end_call(session.session_id) }
end
```

- The log tag and the environment prefix come from the title
  (`Feedia BBS` → `feedia-bbs`, `FEEDIA_BBS_`); when the technical name differs,
  say it: `BBS.board 'WarpEngine BBS', WarpEngineBBS, slug: 'warp-engine-bbs'`.
- The domain class is made once (`BBS.config.board`), its `start` called when
  it has one, and its `services` are what the faces get.
- A face given as a block is a Flow for what comes before the face:
  `modern { |bbs| big_banner 'TTG WIKI'; app UI::Modern::APP }`.
- The goodbye comes after each face by itself (`BBS::Goodbye.show`); never
  call `BBS::Goodbye` from a face. `goodbye false` leaves it out.
- One face only (`modern` without `petscii`): no terminal question.

Grep: `BBS.configure`, `Terminal.flow`, `Goodbye\.`, `TTG::Logo.splash`.

## 2. The domain object: `BBS::Domain`

```ruby
class FeediaBBS
  include BBS::Domain

  setting :refresh, 3600                    # FEEDIA_BBS_REFRESH, cast to the default's type
  setting :languages, %w[en hu]             # an Array default splits on commas
  path    :db, 'data/feedia.sqlite3'        # FEEDIA_BBS_DB, expanded against the board's root (Dir.pwd)

  service(:feeds) { FeedService.new(FeedRepository.new(database(db, *FeedRepository::MIGRATIONS))) }
  service(:inbox) { InboxService.new(feeds) }

  background('feed refresh', every: -> { refresh }) { feeds.refresh }
end
```

`services` (a Hash by name) and `start` (makes every service, begins the
background jobs) come with it. `database(path, Schema)` or
`database(path, *sql_steps)` is a migrated `BBS::SQLite`. Keep plain methods
for anything else. Grep: `ENV.fetch`, `def services`, `ROOT =`, `def setting`.

## 3. Flows

- `call` blocks run in the `BBS::FlowRunner`: `call { context[:x] = session.caller_key }`.
  No `|ctx, runner|`, no trailing `nil`, no `rescue IOError…` (a dropped line
  ends the flow quietly). Grep: `call do |`, `call { |`.
- `app DEFINITION`, `face FaceClass`, `goodbye 'note'`, `flow other_flow` are steps.
- A hang-up is `BBS::Hangup` (an `IOError`); `BBS::LINE_DROPPED` lists the
  errors of a dropped line for a `rescue *BBS::LINE_DROPPED`. Never write
  `rescue IOError, Errno::EPIPE, Errno::ECONNRESET` or `raise IOError, 'hung up'`.

## 4. The modern face: `Application.define`

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

Gone: `menubar do … end`, `status_hint`, `body`, `with_loading`,
`services bbs.services` (the board's services come by themselves),
`statusbar.right_text = …` with a clock in `on_tick`, `F10`/`Alt-X`
(built in as the commands `:menu` and `:log_off`), the Keys text (the Keys
page is written from the commands; only board-specific keys go in `keys:`).
A command's label gets an `&` hotkey by itself when it has none.

In helpers and window blocks, on the application:

| 2.0 | was |
|---|---|
| `message(text, title: 'About')` | `BBS::Dialogs.message(self, text, title: ' About ')` |
| `ask('Title:', title: 'Search') { \|text\| … }` | `Dialogs.input(self, prompt:, on_submit: ->(t) { … unless t.strip.empty? })` |
| `confirm('Sure?') { … }` | `Dialogs.confirm(self, …, on_yes:)` |
| `x = loading('Loading…', failed: NO_ANSWER) { … }` | `x = with_loading('…') { … }; return message(NO_ANSWER) unless x` |
| `fail_with(text)` | `message(text); return` deep in a helper chain |
| `report(result, WORDING)` | `case result when :x then message('…')` |
| `qr(url, title: 'Scan me')` | `BBS::QR.ansi` + `rescue QR::TooLong` + `quiet: 1` + `Windows::Info.open` sizing |
| `show(:article, article: a)` | `open_window(:article, article: a)` |
| `window(:browser)&.selected`, `close_all`, `reload_details` | `windows.grep(MasterDetail).last…`, `close_window while top_window` |
| `catalog` (a service by its name) | `services[:catalog]` |
| `caller_key` | `BBS::RateLimit.caller_key(session)` |
| `markdown(text, width)` | `BBS::Markdown.to_lines(text, width:, theme: theme)` |
| `dim(s)`, `bright(s)`, `accent(s)`, `paint(:error, s)` | `"#{theme[:text_dim]}#{s}#{theme[:text]}"` |
| `refresh_status` | `statusbar.right_text = status_text` |
| `log_off` | `:halt` |
| `with_line { \|session\| … }` (now `session.hand_over`) | `with_line` |

`on_idle { … keep_on }` keeps a caller on (was: return `:keep`).

Titles are plain: the frame pads (and cuts) them. Grep `title: ' `, `" #{`…`} "`.

`BBS::Abort` (raised by `loading … failed:` and `fail_with`) ends the command
quietly: the event loop takes it.

## 5. Windows

```ruby
module UI::Modern::ArticleWindow
  extend BBS::Part

  window :article, :master_detail do          # the type is the 2nd argument
    title      { article.title }              # extras of `show` are methods
    list_width { [26, cols / 4].max }         # or 1/3r; height -8 = rows - 8
    items      { article.sections }
    label      :title                         # a Symbol, or a block |item|
    detail     { |section, width| markdown(section.markdown, width) }   # lines; rubbs wraps long ones
    meta       { |section| "#{article.url} · CC BY-SA" }
    on_pick    { |section| … }                # Enter on the list
    action('QR code') { |section| qr article.short_url }               # keeps the window; `close` closes it
  end
end
```

| 2.0 | 1.x |
|---|---|
| `window :x, :form do … end` (spec block evaluated in the spec) | `window(:x, type: :form) { \|w\| w.… }` |
| blocks without `ctx`, in the application | `{ \|ctx\| ctx[:app].foo(ctx[:article]) }` |
| `label` | `item_label` |
| `detail` | `render_detail` |
| `meta` | `bottom_meta` |
| `on_pick` | `on_activate` |
| `lines` (stream); `keep` in its `on_submit` keeps the typed text | `initial_lines`; return `:keep` |
| `empty` | `empty_message` |
| `action('Open') { \|item\| … }` | `action(label: '&Open') { \|win, ctx\| item = win.list_widget.selected_item; …; :keep }` |
| info `button('Yes') { …; keep }` | `button(label:) { …; :keep }` |
| form: `errors(bad_url: '…')` + `on_submit { \|values\| service.add(values) }` returning the error's key; `error!('…')`; otherwise it closes | `form.error('…'); :keep` / `:close` |
| `maximizable` on by default (master/detail, stream, reader) | `w.maximizable true` |
| `:reader` type: `lines { \|width\| … }`, `where { \|view\| … }`, `max_width 78`, `action('Contents') { \|reader\| reader.jump(i) }` | a hand-made `BBS::Window` subclass with `ButtonBar.attach/place` |

An extra named like a method of the application (`show(:x, rows: …)`) raises
`ArgumentError`: name it otherwise. In a window block `window` is the window,
`selected` the selected item, `form` the form, `close`/`keep`/`error!` as above.

## 6. The line-by-line face: `BBS::Petscii::Face`

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

    # run is: show_masthead, then main_menu_loop (the menu until log off);
    # override it for another shape (main_menu_choice, home, show_masthead).

    private

    def feed_list
      each_pick('FEEDS', feeds.list, label: :title) { |feed| read(feed) }   # the title comes back by itself
    end
  end
end
```

The face answers the screen's methods itself (`puts say title page pick ask
edit pause choose actions menu within`) and the new ones: `alert(text)`
(red + pause), `notice(text)` (green + pause), `prompt('name', hint:, max:)`
(nil when empty), `confirm?(q)`, `number(label, range)`, `each_pick`,
`markdown(text)` (C64 colours, indented), `qr(url)`, `rule_line`,
`within(title, right) { … }` (puts the previous title back), `home` (the home
title), `loading('working…', failed:) { … }`, `fail_with(text)`, `report(result,
WORDING)`, `open_door(door)`, `caller_key`, the board's services as readers,
`dim/bright/accent/paint` with the C64 palette. `BBS::Abort` in a main-menu
item leaves the caller at the menu.

Gone: `Colors.install(self)`, the `COLS`/`WIDTH` constants, the empty
`class Screen < BBS::Petscii::Screen`, `MARKDOWN = { text: LG, … }`
(`Screen::MARKDOWN`), `" #{DG}#{'─' * (COLS - 2)}#{LG}"` (`rule_line`), the
`Selector.item(…, key: 'x', value: 'x')` arrays and `case` on the choice, the
title restored after every sub-screen. `Petscii::Screen#key` raises
`BBS::Hangup`.

## 7. Smaller blocks

More of the DSL, for what most boards needed:

- `main_menu(home: :masthead, above: -> { "#{count} items" }, back: 's')`; the first
  menu stays under the masthead of `run`; `each_of(-> { shelves }) { |shelf, i| item(…) }`
  for items made each round; `item(…, if: -> { user })`; `about` may be a block.
- `alert(text, color: YE)`, `fail_with(text, color:)`; a `BBS::Abort` inside `each_pick`
  leaves the caller at that list.
- `make_screen(session)` in a face for a screen of its own class or size.
- `action('Reload') { … }` without a parameter runs on an empty list too; `meta 'text'`
  takes a value; `maximized true`; a reader's `on_key(left: ->(reader, key) { … })` and
  `reader.reload`; `window(:x).selected` on a master/detail.
- `help({ 'Jargon File' => TEXT }, about: -> { "#{count} pages" }) { item('Rules') { … } }`;
  `status(clock: :before)`; redeclaring `:log_off`/`:menu` keeps their place;
  `loading(…, failed:, title: 'Feed')`; `board` (the domain object) in the application;
  `doors { board.doors }` and `door(a_door)`; `command … key: 'Ctrl-S'`;
  `desktop { widget(fill: true) { Dashboard.new } }`.
- `setting :feed_list, 'x', env: 'FEEDS'`, `setting :irc, 'irc.libera.chat', blank: true`
  (empty means nil), `background(…, if: -> { ttl.positive? })`, and a domain class without
  `BBS.board` takes its prefix from its name (`FeediaBBS` → `FEEDIA_BBS_`) or
  `env_prefix 'X_'`, so tools and tests need not set `BBS.config.env_prefix`.
- `BBS.board`: `idle { |bbs| bbs.idle_seconds }`, `goodbye('note', clear: false, color: GN,
  bar: 'thanks for reading', art: LOGO)`, `goodbye { |context| "#{minutes(context)} on line" }`;
  a face given as a Flow or a block runs in its own runner, so a refusal (`gate`) still
  reaches the goodbye.
- `DR` (dark red) among the C64 colours; `Masthead#line(…, indent: 2)`;
  `Snapshot.new(…, meta: { 'license' => 'CC0-1.0' })`.

- `BBS::Preset` (splash, `url`, `qr`, `user_agent`); `BBS::Goodbye` takes the
  title and the address from `BBS.config`. `Goodbye::URL` and `QR_URL` are gone.
- `Config#user_agent` is `rubbs/<version>` plus the preset's.
- `session.caller_key`, `session.hand_over { … }`.
- `BBS::Door.new(name, program, label:, hint:, about:, petscii:)`: `about` for
  a list of doors, `petscii` a program for a C64 line.
- `BBS::Snapshot.new(seed:, path:, source:) { |records| … }` (`value`,
  `generated_at`, `replace`, `refresh_every(3600, ttl:) { fetch }`) for a catalog
  file kept whole in memory.
- `BBS::Transfer.send(session, protocol, name, data)`, `.start`, `.result`,
  `.label`, `PROTOCOLS`.
- `BBS::Style[fg: 84, bg: 16, bold: true]` for an SGR by colour.
- FakeOS `colors text: :green, dim: { fg: :green, faint: true }`.
- `require 'bbs/test'`: `BBS::Test::Session` (keys in, output kept,
  `petscii:`).
- `BBS::Pages` / `BBS::Page`: a full-screen page app for both faces (a stack
  of pages, keys declared with `key(:up) { … }`, timers with `every(1) { … }`,
  `push`/`back`/`replace`/`quit` instead of `:redraw`/procs/`nil`, only the
  changes repainted, `read_line`, `hand_over`). A board with its own TUI loop,
  view stack or diff writer moves onto it (ttg-gate-bbs is the example).
- `BBS::Petscii::Canvas.new(charset: :lower)` draws in the lower/upper set;
  `Canvas#diff(before)` sends the cheaper of a patch and a full frame. A
  `Canvas` subclass that filtered the glyphs for the lower set goes.
- `BBS::Nodes.new.take { |node| … }`: the lowest free node number for a call.


---

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
