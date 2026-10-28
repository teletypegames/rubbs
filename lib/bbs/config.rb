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
    # [theme]            meant as the default BBS::Theme for applications;
    #                    stored here but not read by the library itself;
    #                    default +nil+
    # [mouse]            whether the board uses mouse reporting at all;
    #                    default +false+
    # [mouse_on_connect] whether a session turns mouse reporting on as soon
    #                    as it connects (when +mouse+ is on); default +true+
    # [idle_seconds]     idle limit in seconds of the Application loop, and
    #                    each connection's socket read/write timeout;
    #                    +nil+ (the default) means no Application limit and
    #                    a 900-second socket timeout
    # [max_sessions]     the most callers served at once; more are turned
    #                    away. Default the +BBS_MAX_SESSIONS+ environment
    #                    variable or 100
    attr_accessor :screens_dir, :flow, :on_session_end,
                  :port, :theme, :mouse, :mouse_on_connect, :idle_seconds, :max_sessions

    # Creates a Config with the defaults, reading +BBS_PORT+ and
    # +BBS_MAX_SESSIONS+ from the environment.
    def initialize
      @port         = (ENV['BBS_PORT'] || 2323).to_i
      @mouse        = false
      @mouse_on_connect = true
      @idle_seconds = nil
      @max_sessions = (ENV['BBS_MAX_SESSIONS'] || 100).to_i
    end
  end
end
