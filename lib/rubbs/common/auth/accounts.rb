# frozen_string_literal: true

require 'time'

module Rubbs
  module Common
    module Auth
      # The schema of the accounts of Rubbs::Common::Auth::Directory, for the board that
      # keeps them (the home of the accounts) to declare as a database of its
      # own:
      #
      #   database :accounts_db, Rubbs::Common::Auth::MIGRATIONS, name: :auth
      MIGRATIONS = [
        <<~SQL,
          CREATE TABLE accounts (
            id              INTEGER PRIMARY KEY,
            name            TEXT NOT NULL,
            name_key        TEXT NOT NULL UNIQUE,
            skeleton        TEXT NOT NULL,
            password_digest TEXT NOT NULL,
            created_at      TEXT NOT NULL,
            last_seen_at    TEXT
          );
          CREATE INDEX accounts_skeleton ON accounts (skeleton);
          CREATE TABLE account_roles (
            account_id INTEGER NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
            role       TEXT NOT NULL,
            granted_at TEXT NOT NULL,
            granted_by TEXT,
            PRIMARY KEY (account_id, role)
          );
        SQL
        <<~SQL
          ALTER TABLE accounts ADD COLUMN banned_at TEXT;
          ALTER TABLE accounts ADD COLUMN banned_by TEXT;
          ALTER TABLE accounts ADD COLUMN ban_reason TEXT;
        SQL
      ].freeze

      # An account: its name as written, the key and skeleton it is found and
      # compared by (Rubbs::Common::Auth::Names), the digest of its password
      # (Rubbs::Common::Auth::Password) and, for a banned account, when, by whom and why
      # (+banned_at+, +banned_by+, +ban_reason+).
      class AccountModel < Storage::Model
        table :accounts, database: :auth

        # The account of +name+ in any case, or +nil+.
        def self.named(name) = where(name_key: Names.key(name)).first

        # Another account that looks like +name+ (Rubbs::Common::Auth::Names.skeleton),
        # or +nil+.
        def self.look_alike(name) = where(skeleton: Names.skeleton(name)).exclude(name_key: Names.key(name)).first

        # The names of every account, in order.
        def self.names = order(:name_key).select_map(:name)

        # The roles of the account, sorted.
        def roles = RoleModel.where(account_id: id).order(:role).select_map(:role)

        # Whether the account is banned (it cannot log in).
        def banned? = !banned_at.nil?
      end

      # A role of an account: a word the boards check (+sysop+, +blogger+), who
      # gave it and when.
      class RoleModel < Storage::Model
        table :account_roles, database: :auth
      end
    end
  end
end
