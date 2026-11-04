# Sample BBS

The sample board of [rubbs](../../README.md): a guestbook on a telnet line,
with both faces a board has, on a modern terminal and on a Commodore 64. It is
small on purpose, and it has every part a real board has, in the place a real
board keeps it. Start a board of your own from it (or from the house template
`devarea/templates/bbs-board` on the Teletype Games network).

```sh
bundle install
bundle exec rake                       # the tests and rake bbs:check
BBS_PORT=2323 bundle exec ruby bbs.rb  # then: telnet localhost 2323
```

## What is where

```
bbs.rb                                  the board: BBS.board with its title, domain and two faces
env-example                             every setting, with its default (SAMPLE_BBS_*)
Rakefile                                BBS::Rake.board: rake test, rake bbs:check, rake
lib/domain.rb                           requires the domain in order
lib/domain/
  sample_bbs.rb                         the domain object: settings, database, services (BBS::Domain)
  migrations.rb                         the schema, one step per version
  model/entry_model.rb                  the entries table: EntryModel < BBS::Model (.all, .where, .create …)
  service/guestbook_service.rb          the rules: answers :ok, :no_name, :empty, :too_long
lib/ui/
  wording.rb                            what both faces say (UI::Wording)
  modern.rb                             the modern face: commands, menu, help, status, desktop
  modern/guestbook_windows.rb           its windows, a BBS::Part: a list and a form
  petscii.rb                            the C64 face: a BBS::Petscii::Face
test/                                   the service and both faces (bbs/test)
```

## How it reads

- **`bbs.rb`** only declares: the title (from which the log tag `sample-bbs` and the
  environment prefix `SAMPLE_BBS_` come), the domain class, the two faces and the goodbye.
- **Each table has its model** in `lib/domain/model` (`EntryModel < BBS::Model`, `table :entries`):
  the queries are its class methods (`EntryModel.newest`), so no SQL is anywhere else. A board
  keeps a repository only for what is not its database (HTTP, files).
- **The domain** knows nothing of telnet. `GuestbookService#sign` answers with a Symbol;
  both faces put it in the words of `UI::Wording::SIGN` (the form with `errors`, the C64
  with `report`).
- **The modern face** says each thing once: `command(:sign, 'Sign…', key: 'F3')` is the
  menu item, the key and the statusbar hint; the Keys page is written from the commands.
  The window blocks run in the application, so `guestbook` is the service itself.
- **The C64 face** is a class: its title bar, masthead and main menu are declared, its
  methods say what an item does; the title comes back by itself after a list.

Each of these is in the rubbs README, and the changes from rubbs 1.x in
[UPGRADING.md](../../UPGRADING.md).
