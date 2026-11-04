# frozen_string_literal: true

module BBS
  module Auth
    # The accounts of the network kept in one board's database (the home of
    # the accounts): logging in, registering, passwords and roles. The other
    # boards ask it through its API (BBS::Auth::API) with a
    # BBS::Auth::Remote, which answers the same.
    #
    #   directory = BBS::Auth::Directory.new(store: databases[:auth])
    #   directory.log_in('tasi', 'secret', caller_key: session.caller_key)   # => an Identity, or :wrong, :locked, :busy
    #
    # The answers are Identity (source +:login+) or a Symbol:
    #
    # [:wrong]      no such name, or not its password
    # [:locked]     too many wrong passwords of late (BBS::Auth::Guard)
    # [:busy]       too many passwords checked at once
    # [:invalid]    not a name an account may have (BBS::Auth::Names::PATTERN)
    # [:taken]      the name has an account
    # [:look_alike] the name looks like another account's
    # [:reserved]   the name is kept for the server's own accounts
    # [:too_short]  the password is shorter than +min_password+
    # [:mismatch]   the password and its confirmation differ
    class Directory
      # The shortest password.
      MIN_PASSWORD = 6

      # A directory in the board's +auth+ database: +store+ keeps the counts
      # of wrong passwords (a Sequel::Database, or +nil+ for memory);
      # +reserved+ names no caller may register (and their look-alikes);
      # +roles+ are what a new account gets.
      def initialize(store: nil, reserved: [], roles: [], min_password: MIN_PASSWORD, guard: nil)
        @guard        = guard || Guard.new(store: store)
        @reserved     = reserved.map { |name| Names.skeleton(name) }
        @roles        = roles.map(&:to_s)
        @min_password = min_password
      end

      # Whether +name+ has an account.
      def known?(name) = !AccountModel.named(name).nil?

      # Whether +name+ has an account: +:known+ or +:unknown+ (a Remote may
      # also answer +:unavailable+: it cannot say).
      def account_state(name) = known?(name) ? :known : :unknown

      # Whether +name+ looks like the name of another account.
      def look_alike?(name) = !AccountModel.look_alike(name).nil?

      # The Identity of +name+ with +password+ from the line +caller_key+, or
      # +:wrong+, +:locked+, +:busy+.
      def log_in(name, password, caller_key:)
        return locked(name) if @guard.locked?(name, caller_key)

        account = AccountModel.named(name)
        return failed(name, caller_key) unless Password.match?(account&.password_digest, password)

        welcome(account, password)
      rescue Password::Busy
        :busy
      end

      # A new account of +name+ with +password+ (said twice): its Identity, or
      # why not (+:invalid+, +:reserved+, +:taken+, +:look_alike+,
      # +:too_short+, +:mismatch+, +:busy+).
      def register(name, password, confirm = password)
        clean = Names.clean(name)
        problem = registration_problem(clean, password, confirm)
        return problem.tap { Auth.event(:register_refused, reason: problem.to_s) } if problem

        identity(create(clean, Password.digest(password), @roles, by: 'register')).tap do |found|
          Auth.event(:register, name: found.name)
        end
      rescue Password::Busy
        :busy
      end

      # Sets the password of +name+ to +password+, the account made when there
      # is none (the server's own tool: no reserved names, no look-alike
      # check). +:ok+, +:invalid+ or +:too_short+.
      def set_password(name, password)
        return :too_short if password.to_s.length < @min_password

        clean = Names.clean(name) or return :invalid
        account = AccountModel.named(clean)
        digest  = Password.digest(password)
        account ? account.update(password_digest: digest) : create(clean, digest, @roles, by: 'server')
        :ok
      end

      # Changes the password of +name+ from +old+ to +fresh+: +:ok+, +:wrong+,
      # +:locked+, +:too_short+ or +:busy+.
      def change_password(name, old, fresh, caller_key:)
        return :too_short if fresh.to_s.length < @min_password

        found = log_in(name, old, caller_key: caller_key)
        return found if found.is_a?(Symbol)

        AccountModel.named(name).update(password_digest: Password.digest(fresh))
        Auth.event(:password, name: found.name)
        :ok
      rescue Password::Busy
        :busy
      end

      # Gives +name+ the +role+ (by +by+). +:ok+ or +:unknown+.
      def grant(name, role, by: nil)
        account = AccountModel.named(name) or return :unknown
        RoleModel.dataset.insert_conflict.insert(account_id: account.id, role: role.to_s, granted_at: now, granted_by: by)
        Auth.event(:grant, name: account.name, role: role.to_s, by: by.to_s)
        :ok
      end

      # Takes +role+ from +name+. +:ok+ or +:unknown+.
      def revoke(name, role)
        account = AccountModel.named(name) or return :unknown
        RoleModel.where(account_id: account.id, role: role.to_s).delete
        Auth.event(:revoke, name: account.name, role: role.to_s)
        :ok
      end

      # The Identity of the account of +name+ (source +:login+), or +nil+.
      def find(name) = AccountModel.named(name)&.then { |account| identity(account) }

      # The names of every account.
      def names = AccountModel.names

      # The accounts in numbers, for a dashboard: +accounts+, +roles+ (a Hash
      # of role => accounts), and the accounts made (+new_day+, +new_week+)
      # and logged in (+seen_day+, +seen_week+) in the last day and week.
      def statistics(now: Time.now)
        day  = (now - 86_400).utc.iso8601
        week = (now - (7 * 86_400)).utc.iso8601
        {
          accounts:  AccountModel.count,
          roles:     RoleModel.group_and_count(:role).to_h { |row| [row[:role], row[:count]] },
          new_day:   since(:created_at, day),
          new_week:  since(:created_at, week),
          seen_day:  since(:last_seen_at, day),
          seen_week: since(:last_seen_at, week)
        }
      end

      # Brings in an account made elsewhere (an import): +digest+ as
      # BBS::Auth::Password keeps it, +id+ to keep one, +roles+. Joins the
      # roles to an account of the name that is there already. Returns its
      # Identity.
      def import(name, digest, roles: [], id: nil, created_at: nil)
        account = AccountModel.named(name)
        account ||= create(name, digest, [], by: 'import', id: id, created_at: created_at)
        roles.each { |role| grant(account.name, role, by: 'import') }
        identity(AccountModel[account.id])
      end

      private

      def failed(name, caller_key)
        @guard.failed(name, caller_key)
        Auth.event(:login_failed, level: :warn, name: name.to_s[0, 40])
        :wrong
      end

      # The Identity of +account+ just logged in with +password+: its digest
      # renewed when it is of fewer iterations, its last login noted.
      def welcome(account, password)
        account.update(password_digest: Password.digest(password)) if Password.rehash?(account.password_digest)
        account.update(last_seen_at: now)
        found = identity(account)
        Auth.event(:login, name: found.name, roles: found.roles.join(','))
        found
      end

      # The accounts whose +column+ is +time+ (ISO 8601) or later.
      def since(column, time) = AccountModel.where(Sequel[column] >= time).count

      def locked(name)
        Auth.event(:locked, level: :warn, name: name.to_s[0, 40])
        :locked
      end

      def registration_problem(name, password, confirm)
        return :invalid    if name.nil?
        return :reserved   if @reserved.include?(Names.skeleton(name))
        return :taken      if known?(name)
        return :look_alike if look_alike?(name)
        return :too_short  if password.to_s.length < @min_password

        :mismatch unless password == confirm
      end

      def create(name, digest, roles, by:, id: nil, created_at: nil)
        row = {
          name:            name,
          name_key:        Names.key(name),
          skeleton:        Names.skeleton(name),
          password_digest: digest,
          created_at:      created_at || now
        }
        account = AccountModel[AccountModel.insert(**{ id: id }.compact, **row)]
        roles.each { |role| RoleModel.insert(account_id: account.id, role: role, granted_at: now, granted_by: by) }
        account
      end

      def identity(account) = Identity.new(id: account.id, name: account.name, roles: account.roles, source: :login)

      def now = Time.now.utc.iso8601
    end
  end
end
