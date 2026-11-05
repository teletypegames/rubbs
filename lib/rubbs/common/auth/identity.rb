# frozen_string_literal: true

module Rubbs
  module Common
    module Auth
      # Who is on the line: a signed-in account (+id+, +name+, +roles+) or a
      # guest (no +id+; a guest may still have the name they gave). +source+
      # says how the board knows: +:token+ (a RUBBS_AUTH_KEY from the board
      # the call came through), +:login+ (a name and password here) or
      # +:guest+.
      #
      #   identity.signed_in?        # => true
      #   identity.role?(:blogger)   # => true when it has that role
      Identity = Data.define(:id, :name, :roles, :source) do
        # A guest, with the +name+ they gave or none.
        def self.guest(name = nil) = new(name: name)

        # An identity; +roles+ are kept as sorted, unique Strings.
        def initialize(id: nil, name: nil, roles: [], source: :guest)
          super(id: id, name: name&.to_s, roles: Array(roles).map(&:to_s).uniq.sort.freeze, source: source.to_sym)
        end

        # Whether no account stands behind it.
        def guest? = id.nil?

        # Whether an account stands behind it.
        def signed_in? = !guest?

        # Whether it has any of +roles+ (Symbols or Strings).
        def role?(*roles) = roles.any? { |role| self.roles.include?(role.to_s) }
      end
    end
  end
end
