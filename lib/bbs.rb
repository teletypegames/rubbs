# frozen_string_literal: true

require_relative 'bbs/config'
require_relative 'bbs/telnet'
require_relative 'bbs/banner'
require_relative 'bbs/flow'
require_relative 'bbs/flow_runner'
require_relative 'bbs/renderer'
require_relative 'bbs/store'
require_relative 'bbs/session'
require_relative 'bbs/server'

module BBS
  def self.configure
    yield(@config ||= Config.new)
  end

  def self.config
    @config ||= Config.new
  end

  def self.start(port: (ENV['BBS_PORT'] || 2323).to_i)
    Server.new(port: port).run
  end
end
