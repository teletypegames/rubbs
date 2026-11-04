# frozen_string_literal: true

module BBS
  # The board's domain object, declared: its settings from the environment,
  # its files, its services and its background work. A board's class
  # includes it and says what it has; BBS.board makes one at boot and calls
  # #start.
  #
  #   class FeediaBBS
  #     include BBS::Domain
  #
  #     setting :refresh, 3600                       # FEEDIA_BBS_REFRESH, an Integer
  #     path     :db, 'data/feedia.sqlite3'          # FEEDIA_BBS_DB, against the board's root
  #     database :db, MIGRATIONS                     # opened at start, BBS::Model classes bound
  #
  #     service(:feeds) { FeedService.new }
  #     service(:inbox) { InboxService.new(feeds) }
  #
  #     background('catalog refresh', every: -> { refresh }) { feeds.refresh }
  #   end
  #
  # A service is made on first use, in the order the board uses them, so one
  # can use another. #services hands them all to the faces by name.
  module Domain
    # Adds the class macros (ClassMethods) to +base+.
    def self.included(base)
      base.extend(ClassMethods)
    end

    # The declarations of a domain class.
    module ClassMethods
      # The board's root folder, where #path resolves relative files: the
      # current directory, where +bbs.rb+ runs, unless set.
      attr_writer :root

      # The board's root folder (see #root=).
      def root = @root || Dir.pwd

      # The prefix of the board's environment variables: BBS::Config#env_prefix
      # (set by BBS.board), else the one declared with <tt>env_prefix
      # 'FEEDIA_BBS_'</tt>, else the class name's (+FeediaBBS+ →
      # +FEEDIA_BBS_+), so a tool or a test can make the domain object without
      # BBS.board.
      def env_prefix(value = nil)
        return @env_prefix = value if value

        BBS.config.env_prefix || @env_prefix || "#{name.gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
                                                      .gsub(/([a-z\d])([A-Z])/, '\\1_\\2').upcase}_"
      end

      # The declared services, settings and background jobs, in order.
      def declared = @declared ||= { services: [], settings: {}, variables: {}, jobs: [], databases: {} }

      # The environment variables the settings read, full names with
      # #env_prefix: what a board's +env-example+ lists.
      def environment_variables = declared[:variables].values.map { |variable| "#{env_prefix}#{variable}" }

      # Declares the setting +name+: an instance method that reads
      # <tt><env_prefix><NAME></tt> from the environment, else +default+.
      # The value takes the type of +default+: an Integer, a Float, +true+
      # or +false+ (<tt>1/true/yes/on</tt>), or a String; an Array default
      # splits the value on commas.
      #
      # [env]   the variable's name after the prefix, when it is not the
      #         method's (<tt>env: 'FEEDS'</tt> for a method +feed_list+)
      # [blank] +true+ when an empty value means "none" (+nil+) instead of
      #         the default
      def setting(name, default = nil, env: nil, blank: false)
        declared[:settings][name] = default
        variable = (env || name).to_s.upcase
        declared[:variables][name] = variable
        domain = self
        define_method(name) do
          settings.fetch(name) { settings[name] = Domain.read(variable, default, blank: blank, prefix: domain.env_prefix) }
        end
      end

      # Declares the file setting +name+: like #setting, the value expanded
      # against #root.
      def path(name, default, **)
        setting(name, default, **)
        reader = instance_method(name)
        define_method(name) { File.expand_path(reader.bind_call(self), self.class.root) }
      end

      # Declares the service +name+: an instance method that makes it with
      # the block (evaluated in the domain object) on first use.
      def service(name, &block)
        declared[:services] << name
        define_method(name) { services_made.fetch(name) { services_made[name] = instance_exec(&block) } }
      end

      # Declares a database of the board: the file of the +path+ setting
      # +setting+, migrated by +migrations+ (BBS::Database.migrate), named
      # +name+ (+:main+ for the first). #start opens it and binds the
      # BBS::Model classes whose table lives in it; #databases has it.
      #
      #   path     :db, 'data/feedia.sqlite3'
      #   database :db, MIGRATIONS
      def database(setting, migrations = [], name: :main)
        declared[:databases][name.to_sym] = [setting, migrations]
      end

      # Declares background work that #start begins (BBS.background): its
      # +name+ for the log, +every+ seconds (a number, or a block evaluated
      # in the domain object, or +nil+ for once), +if+ a block (in the domain
      # object) that must answer true for the work to begin, and the other
      # options of BBS.background.
      def background(name, every: nil, if: nil, **options, &work)
        declared[:jobs] << [name, every, binding.local_variable_get(:if), options, work]
      end
    end

    # The value of the environment variable +name+ after +prefix+, in the
    # type of +default+; +default+ when it is not set, or empty (+nil+ for an
    # empty one with +blank+).
    def self.read(name, default, blank: false, prefix: BBS.config.env_prefix)
      raw = ENV.fetch("#{prefix}#{name.to_s.upcase}", nil)
      return default if raw.nil?
      return (blank ? nil : default) if raw.strip.empty?

      cast(raw.strip, default)
    end

    # +raw+ in the type of +default+ (see ClassMethods#setting).
    def self.cast(raw, default)
      case default
      when Integer     then Integer(raw, 10)
      when Float       then Float(raw)
      when true, false then %w[1 true yes on].include?(raw.downcase)
      when Array       then raw.split(',').map(&:strip).reject(&:empty?)
      else raw
      end
    end

    # The services by name, made now: what an Application and a
    # BBS::Petscii::Face get.
    def services = self.class.declared[:services].to_h { |name| [name, public_send(name)] }

    # The board's databases by name, opened and migrated on first use
    # (Sequel::Database each); the BBS::Model classes are bound to them.
    def databases
      return @databases if @databases

      @databases = self.class.declared[:databases].to_h do |name, (setting, migrations)|
        [name, Database.open(public_send(setting), migrations)]
      end
      Model.bind(@databases)
      @databases
    end

    # Opens the databases, makes every service and begins the background
    # work. BBS.board calls it once at boot. Returns +self+.
    def start
      databases
      services
      self.class.declared[:jobs].each do |name, every, condition, options, work|
        next if condition && !instance_exec(&condition)

        seconds = every.is_a?(Proc) ? instance_exec(&every) : every
        BBS.background(name, every: seconds, **options) { instance_exec(&work) }
      end
      self
    end

    private

    def settings = @settings ||= {}

    def services_made = @services_made ||= {}
  end
end
