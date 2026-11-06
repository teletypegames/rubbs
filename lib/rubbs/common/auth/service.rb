# frozen_string_literal: true

module Rubbs
  module Common
    module Auth
      # The accounts as a service of the Central (Rubbs::Common::Central), on
      # <tt>/auth</tt>: what Rubbs::Common::Auth::Remote asks the board that
      # keeps the accounts. Its ops do not ask who calls (the caller is not
      # signed in yet); their fields:
      #
      # [log_in]          +name+, +password+, +caller_key+
      # [register]        +name+, +password+, +confirm+
      # [change_password] +name+, +password+, +fresh+, +caller_key+
      # [known]           +name+
      # [look_alike]      +name+
      #
      # The answer is <tt>{ "result": "ok", "token": … }</tt> (a token of the
      # account for the asking board) or <tt>{ "result": "wrong" }</tt> and
      # the like, the Symbols of Rubbs::Common::Auth::Directory; +known+ and
      # +look_alike+ answer +true+ or +false+.
      class Service < Central::Service
        path '/auth'

        op(:known, actor: false) { |_, name: '', **| { result: directory.known?(name.to_s) } }
        op(:look_alike, actor: false) { |_, name: '', **| { result: directory.look_alike?(name.to_s) } }

        op(:log_in, actor: false) do |_, name: '', password: '', caller_key: '', **|
          outcome(directory.log_in(name.to_s, password.to_s, caller_key: caller_key.to_s))
        end

        op(:register, actor: false) do |_, name: '', password: '', confirm: '', **|
          outcome(directory.register(name.to_s, password.to_s, confirm.to_s))
        end

        op(:change_password, actor: false) do |_, name: '', password: '', fresh: '', caller_key: '', **|
          outcome(directory.change_password(name.to_s, password.to_s, fresh.to_s, caller_key: caller_key.to_s))
        end

        # The Central's accounts, a Rubbs::Common::Auth::Directory.
        def directory = context.accounts

        private

        def outcome(result)
          return result if result.is_a?(Symbol)
          return :ok unless result.is_a?(Identity)

          { result: 'ok', token: Token.issue(result, aud: asker) }
        end
      end
    end
  end
end
