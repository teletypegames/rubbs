# frozen_string_literal: true

require_relative 'bbs/color'
require_relative 'bbs/config'
require_relative 'bbs/telnet'
require_relative 'bbs/banner'
require_relative 'bbs/flow'
require_relative 'bbs/flow_runner'
require_relative 'bbs/renderer'
require_relative 'bbs/store'
require_relative 'bbs/frame_buffer'
require_relative 'bbs/event'
require_relative 'bbs/theme'
require_relative 'bbs/widget'
require_relative 'bbs/container'
require_relative 'bbs/widgets'
require_relative 'bbs/widgets/ansi_art'
require_relative 'bbs/window'
require_relative 'bbs/focus_manager'
require_relative 'bbs/menu'
require_relative 'bbs/statusbar'
require_relative 'bbs/dialogs'
require_relative 'bbs/markdown'
require_relative 'bbs/windows/button_bar'
require_relative 'bbs/windows/info'
require_relative 'bbs/windows/form'
require_relative 'bbs/windows/master_detail'
require_relative 'bbs/windows/stream'
require_relative 'bbs/application'
require_relative 'bbs/tui'
require_relative 'bbs/tui_runner'
require_relative 'bbs/session'
require_relative 'bbs/server'

module BBS
  def self.configure
    yield(@config ||= Config.new)
  end

  def self.config
    @config ||= Config.new
  end

  def self.start(port: config.port)
    Server.new(port: port).run
  end
end
