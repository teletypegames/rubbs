# frozen_string_literal: true

module BBS
  class Config
    attr_accessor :screens_dir, :flow, :on_session_end,
                  :port, :theme, :mouse, :idle_seconds, :max_sessions

    def initialize
      @port         = (ENV['BBS_PORT'] || 2323).to_i
      @mouse        = false
      @idle_seconds = nil
      @max_sessions = 100
    end
  end
end
