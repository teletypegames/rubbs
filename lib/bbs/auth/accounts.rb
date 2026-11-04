# frozen_string_literal: true

require 'time'

module BBS
  module Auth
    # The schema of the accounts of BBS::Auth::Directory, for the board that
    # keeps them (the home of the accounts) to declare as a database of its
    # own:
    #
    #   database :accounts_db, BBS::Auth::MIGRATIONS, name: :auth
    MIGRATIONS = [
      <<~SQL
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
    ].freeze

    # An account: its name as written, the key and skeleton it is found and
    # compared by (BBS::Auth::Names) and the digest of its password
    # (BBS::Auth::Password).
    class AccountModel < Model
      table :accounts, database: :auth

      # The account of +name+ in any case, or +nil+.
      def self.named(name) = where(name_key: Names.key(name)).first

      # Another account that looks like +name+ (BBS::Auth::Names.skeleton),
      # or +nil+.
      def self.look_alike(name) = where(skeleton: Names.skeleton(name)).exclude(name_key: Names.key(name)).first

      # The names of every account, in order.
      def self.names = order(:name_key).select_map(:name)

      # The roles of the account, sorted.
      def roles = RoleModel.where(account_id: id).order(:role).select_map(:role)
    end

    # A role of an account: a word the boards check (+sysop+, +blogger+), who
    # gave it and when.
    class RoleModel < Model
      table :account_roles, database: :auth
    end
  end
end
