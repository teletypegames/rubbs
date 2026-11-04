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
    # [log_tag]          what every BBS.log line starts with, the board's
    #                    technical name such as <tt>feedia-bbs</tt>; default
    #                    the +BBS_LOG_TAG+ environment variable or +bbs+
    # [title]            the board's name as callers read it, <tt>Feedia
    #                    BBS</tt>; set by BBS.board, default +nil+
    # [env_prefix]       the prefix of the board's own environment variables,
    #                    <tt>FEEDIA_BBS_</tt>, read by BBS::Domain#setting;
    #                    set by BBS.board, default +nil+
    # [preset]           the BBS::Preset of the board; default
    #                    BBS::Preset::NONE
    # [board]            the board's domain object (the class given to
    #                    BBS.board, made once at boot): its +services+ are
    #                    the default services of an Application, and a
    #                    BBS::Petscii::Face gets it; default +nil+
    attr_accessor :screens_dir,
                  :flow,
                  :on_session_end,
                  :port,
                  :theme,
                  :mouse,
                  :mouse_on_connect,
                  :idle_seconds,
                  :max_sessions,
                  :max_sessions_per_ip,
                  :ai_concurrency,
                  :log_tag,
                  :title,
                  :env_prefix,
                  :preset,
                  :board

    # [log_format]       how BBS.log writes a line: +:text+ (the default)
    #                    or +:json+, one object a line for a log pipeline;
    #                    the +BBS_LOG_FORMAT+ environment variable sets it
    # [shutdown_seconds] how long a stopping server (SIGTERM, Ctrl-C) waits
    #                    for its callers after telling them, before it
    #                    hangs up on the rest; default the
    #                    +BBS_SHUTDOWN_SECONDS+ environment variable or 8
    #                    (within the 10 seconds of <tt>docker stop</tt>)
    # [shutdown_notice]  what the callers of a stopping server are told;
    #                    <tt>%<seconds>d</tt> is replaced by the seconds left
    # [health]           callable the health probe (BBS::Health) asks: it
    #                    returns the board's problems, an Array of Strings,
    #                    empty when it is well; set by BBS.board from the
    #                    domain's +health+, default +nil+ (always well)
    attr_accessor :log_format, :shutdown_seconds, :shutdown_notice, :health

    # The User-Agent of BBS::HTTP without a preset's addition.
    DEFAULT_USER_AGENT = "rubbs/#{Gem.loaded_specs['bbs']&.version || 'dev'}".freeze

    # Sets the User-Agent of BBS::HTTP requests, overriding the derived one.
    attr_writer :user_agent

    # The User-Agent header of BBS::HTTP requests: the one set with
    # #user_agent=, else DEFAULT_USER_AGENT followed by the preset's
    # +user_agent+.
    def user_agent
      @user_agent || [DEFAULT_USER_AGENT, @preset.user_agent].compact.join(' ')
    end

    # The default #shutdown_notice.
    SHUTDOWN_NOTICE = 'The board is restarting in %<seconds>d seconds. Please call back in a minute.'

    # Creates a Config with the defaults, reading +BBS_PORT+,
    # +BBS_MAX_SESSIONS+, +BBS_MAX_SESSIONS_PER_IP+, +BBS_LOG_TAG+,
    # +BBS_LOG_FORMAT+ and +BBS_SHUTDOWN_SECONDS+ from the environment.
    def initialize
      @port         = (ENV['BBS_PORT'] || 2323).to_i
      @mouse        = false
      @mouse_on_connect = true
      @idle_seconds = nil
      @max_sessions = (ENV['BBS_MAX_SESSIONS'] || 100).to_i
      @max_sessions_per_ip = (ENV['BBS_MAX_SESSIONS_PER_IP'] || 6).to_i
      @ai_concurrency      = 2
      @user_agent          = nil
      @log_tag             = ENV['BBS_LOG_TAG'] || 'bbs'
      @preset              = Preset::NONE
      @log_format          = (ENV['BBS_LOG_FORMAT'] || 'text').to_sym
      @shutdown_seconds    = (ENV['BBS_SHUTDOWN_SECONDS'] || 8).to_f
      @shutdown_notice     = SHUTDOWN_NOTICE
    end
  end
end
