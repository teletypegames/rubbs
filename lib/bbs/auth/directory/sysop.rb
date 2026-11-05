# frozen_string_literal: true

module BBS
  module Auth
    class Directory
      # The sysop's side of a Directory: the list of the accounts and bans.
      # A banned account cannot log in (Directory#log_in answers +:banned+
      # once the password is right), so it gets no token either.
      #
      #   directory.ban('spammer', by: 'Tasi', reason: 'ads in the forum')
      #   directory.accounts('sysop')   # => the Entry of every sysop
      module Sysop
        # An account as a sysop's list shows it (#accounts, #entry): +id+,
        # +name+, +roles+ (sorted Strings), +created_at+ and +last_seen_at+
        # (ISO 8601, +last_seen_at+ +nil+ before the first login), and for a
        # banned account +banned_at+, +banned_by+ and +ban_reason+.
        Entry = Data.define(:id, :name, :roles, :created_at, :last_seen_at, :banned_at, :banned_by, :ban_reason) do
          # Whether the account is banned.
          def banned? = !banned_at.nil?
        end

        # Bans the account of +name+ (by +by+, for +reason+): it cannot log in
        # any more (#log_in answers +:banned+), nor get a token through the API.
        # The calls it is on go on until the board hangs them up
        # (BBS::Session#hang_up). +:ok+ or +:unknown+.
        def ban(name, by:, reason: nil)
          account = AccountModel.named(name) or return :unknown
          account.update(banned_at: now, banned_by: by.to_s, ban_reason: reason.to_s.strip[0, 200])
          Auth.event(:ban, level: :warn, name: account.name, by: by.to_s)
          :ok
        end

        # Lifts the ban of +name+ (by +by+). +:ok+ or +:unknown+.
        def unban(name, by:)
          account = AccountModel.named(name) or return :unknown
          account.update(banned_at: nil, banned_by: nil, ban_reason: nil)
          Auth.event(:unban, name: account.name, by: by.to_s)
          :ok
        end

        # Every account as an Entry, by name; with +query+ only those whose
        # name has it (in any case) or that have a role of it.
        def accounts(query = nil)
          roles = RoleModel.order(:role).to_hash_groups(:account_id, :role)
          list  = AccountModel.order(:name_key).all.map { |account| entry_of(account, roles[account.id] || []) }
          query.to_s.strip.empty? ? list : matching(list, query.strip)
        end

        # The Entry of the account of +name+, or +nil+.
        def entry(name) = AccountModel.named(name)&.then { |account| entry_of(account, account.roles) }

        private

        def banned(account)
          Auth.event(:login_banned, level: :warn, name: account.name)
          :banned
        end

        def entry_of(account, roles)
          Entry.new(
            id:           account.id,
            name:         account.name,
            roles:        roles,
            created_at:   account.created_at,
            last_seen_at: account.last_seen_at,
            banned_at:    account.banned_at,
            banned_by:    account.banned_by,
            ban_reason:   account.ban_reason
          )
        end

        def matching(list, query)
          key = Names.key(query)
          list.select { |e| Names.key(e.name).include?(key) || e.roles.include?(key) }
        end
      end
    end
  end
end
