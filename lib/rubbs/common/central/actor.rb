# frozen_string_literal: true

module Rubbs
  module Common
    module Central
      # Who asks the Central: an account (+id+, +name+, +roles+) or a guest (no
      # +id+, the +name+ they gave or none), with the +caller_key+ of their
      # line (Rubbs::Common::Line::RateLimit.caller_key) and the +face+ they
      # call on.
      #
      # A board makes one from the session (Actor.of) and sends it with the
      # request (#to_wire: the id and name of an account, never its roles);
      # the Central checks it once (Rubbs::Common::Central::Server) and hands
      # the service the Actor it made itself, with the roles the accounts say.
      #
      #   actor = Actor.of(session)                 # the caller on the line
      #   actor = Actor.of(session, name: 'Joe')    # a guest who gave a name
      Actor = Data.define(:id, :name, :roles, :caller_key, :face) do
        # The actor of the caller on +session+: their account, or a guest
        # with +name+ (else the name their identity has, if any).
        def self.of(session, name: nil)
          identity = session.identity
          face     = session.respond_to?(:face) ? session.face : nil
          return new(id: identity.id, name: identity.name, caller_key: session.caller_key, face: face) if identity.signed_in?

          guest(name || identity.name, caller_key: session.caller_key, face: face)
        end

        # A guest with +name+ (+nil+: no name).
        def self.guest(name = nil, caller_key: nil, face: nil) = new(name: name, caller_key: caller_key, face: face)

        # Nobody in particular: what a service gets for an op that does not
        # ask who calls.
        def self.nobody = new

        # An actor; +roles+ are kept as sorted, unique Strings.
        def initialize(id: nil, name: nil, roles: [], caller_key: nil, face: nil)
          roles = Array(roles).map(&:to_s).uniq.sort.freeze
          super(id: id, name: name&.to_s, roles: roles, caller_key: caller_key&.to_s, face: face&.to_s)
        end

        # Whether no account stands behind it.
        def guest? = id.nil?

        # Whether an account stands behind it.
        def account? = !guest?

        # Whether it has any of +roles+ (Symbols or Strings).
        def role?(*roles) = roles.any? { |role| self.roles.include?(role.to_s) }

        # What a board sends: <tt>{ "id", "name" }</tt> for an account,
        # <tt>{ "guest" }</tt> for a guest, with +caller_key+ and +face+.
        def to_wire
          who = account? ? { 'id' => id, 'name' => name } : { 'guest' => name }
          who.merge('caller_key' => caller_key, 'face' => face).compact
        end
      end
    end
  end
end
