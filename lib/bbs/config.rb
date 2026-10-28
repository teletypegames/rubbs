# frozen_string_literal: true

module BBS
  class Config
    attr_accessor :screens_dir, :flow, :on_session_end,
                  :port, :theme, :mouse, :mouse_on_connect, :idle_seconds, :max_sessions

    def initialize
      @port         = (ENV['BBS_PORT'] || 2323).to_i
      @mouse        = false
      @mouse_on_connect = true
      @idle_seconds = nil
      @max_sessions = (ENV['BBS_MAX_SESSIONS'] || 100).to_i
    end
  end
end
