# frozen_string_literal: true

module BBS
  # The global settings of the BBS, kept in BBS.config and set with
  # BBS.configure. A new Config holds the defaults below.
  class Config
    # [screens_dir]      directory of the ERB screens BBS::Renderer and
    #                    <tt>Flow#screen</tt> read when the flow has no
    #                    +screens_dir+ of its own; default +nil+
    # [flow]             the BBS::Flow every new BBS::Session runs; must be
    #                    set before BBS.start
    # [on_session_end]   callable invoked as <tt>call(session)</tt> from the
    #                    server thread after each session ends, even on an
    #                    error; default +nil+
    # [port]             TCP port BBS.start listens on; default the
    #                    +BBS_PORT+ environment variable or 2323
    # [theme]            the BBS::Theme of every Application that does not
    #                    set one with its own +theme+ call; +nil+ (the
    #                    default) means BBS::Theme.synchronet
    # [mouse]            whether the board uses mouse reporting at all;
    #                    default +false+
    # [mouse_on_connect] whether a session turns mouse reporting on as soon
    #                    as it connects (when +mouse+ is on); default +true+
    # [idle_seconds]     idle limit in seconds of the Application loop and
    #                    each connection's socket read/write
    #                    timeout; each session starts with it and may change
    #                    its own (<tt>Session#idle_seconds=</tt>);
    #                    +nil+ (the default) means no Application limit and
    #                    a 900-second socket timeout
    # [max_sessions]     the most callers served at once; more are turned
    #                    away. Default the +BBS_MAX_SESSIONS+ environment
    #                    variable or 100
    # [max_sessions_per_ip] the most callers served at once from one public
    #                    address; local ones (a proxy on the Docker network,
    #                    see BBS::Address.local?) are not limited. Default
    #                    the +BBS_MAX_SESSIONS_PER_IP+ environment variable
    #                    or 6
    # [ai_concurrency]   the most BBS::AI::Client requests running at once in
    #                    the process; default 2
    # [user_agent]       the User-Agent header of BBS::HTTP requests;
    #                    default <tt>rubbs/<version> (+https://teletypegames.org)</tt>
    # [log_tag]          what every BBS.log line starts with, the board's
    #                    technical name such as <tt>feedia-bbs</tt>; default
    #                    the +BBS_LOG_TAG+ environment variable or +bbs+
    attr_accessor :screens_dir, :flow, :on_session_end,
                  :port, :theme, :mouse, :mouse_on_connect, :idle_seconds, :max_sessions,
                  :max_sessions_per_ip, :ai_concurrency, :user_agent, :log_tag

    # The User-Agent of BBS::HTTP when none is configured.
    DEFAULT_USER_AGENT = "rubbs/#{Gem.loaded_specs['bbs']&.version || 'dev'} (+https://teletypegames.org)".freeze

    # Creates a Config with the defaults, reading +BBS_PORT+,
    # +BBS_MAX_SESSIONS+, +BBS_MAX_SESSIONS_PER_IP+ and +BBS_LOG_TAG+ from
    # the environment.
    def initialize
      @port         = (ENV['BBS_PORT'] || 2323).to_i
      @mouse        = false
      @mouse_on_connect = true
      @idle_seconds = nil
      @max_sessions = (ENV['BBS_MAX_SESSIONS'] || 100).to_i
      @max_sessions_per_ip = (ENV['BBS_MAX_SESSIONS_PER_IP'] || 6).to_i
      @ai_concurrency      = 2
      @user_agent          = DEFAULT_USER_AGENT
      @log_tag             = ENV['BBS_LOG_TAG'] || 'bbs'
    end
  end
end
