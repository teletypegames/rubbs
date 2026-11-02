# frozen_string_literal: true

require_relative 'bbs/ansi'
require_relative 'bbs/ascii'
require_relative 'bbs/text'
require_relative 'bbs/address'
require_relative 'bbs/patterns'
require_relative 'bbs/config'
require_relative 'bbs/petscii'
require_relative 'bbs/telnet'
require_relative 'bbs/text_buffer'
require_relative 'bbs/cursor'
require_relative 'bbs/field'
require_relative 'bbs/selector'
require_relative 'bbs/editor'
require_relative 'bbs/petscii/colors'
require_relative 'bbs/petscii/screen'
require_relative 'bbs/petscii/canvas'
require_relative 'bbs/petscii/canvas_menu'
require_relative 'bbs/art'
require_relative 'bbs/season'
require_relative 'bbs/block_font'
require_relative 'bbs/goodbye'
require_relative 'bbs/discord_webhook'
require_relative 'bbs/banner'
require_relative 'bbs/flow'
require_relative 'bbs/flow_runner'
require_relative 'bbs/terminal'
require_relative 'bbs/fake_os'
require_relative 'bbs/ai'
require_relative 'bbs/door'
require_relative 'bbs/gateway'
require_relative 'bbs/gateway/ascii_bridge'
require_relative 'bbs/zmodem'
require_relative 'bbs/xmodem'
require_relative 'bbs/renderer'
require_relative 'bbs/sqlite'
require_relative 'bbs/store'
require_relative 'bbs/http'
require_relative 'bbs/cache'
require_relative 'bbs/rate_limit'
require_relative 'bbs/background'
require_relative 'bbs/wikipedia'
require_relative 'bbs/frame_buffer'
require_relative 'bbs/event'
require_relative 'bbs/theme'
require_relative 'bbs/widget'
require_relative 'bbs/container'
require_relative 'bbs/widgets'
require_relative 'bbs/widgets/scene'
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
require_relative 'bbs/session'
require_relative 'bbs/server'

# The +bbs+ gem: a library for telnet BBS servers. Requiring it loads the
# whole library. Configure it with BBS.configure, then start the server with
# BBS.start:
#
#   require 'bbs'
#
#   BBS.configure do |c|
#     c.port = 2323
#     c.flow = MY_FLOW
#   end
#   BBS.start
#
# See README.md for the guide.
module BBS
  # Yields the global BBS::Config (created on first use) so the block can set
  # its fields. Returns the block's value.
  def self.configure = yield(config)

  # The global BBS::Config, created with its defaults on first use.
  def self.config
    @config ||= Config.new
  end

  # Starts a BBS::Server listening on +port+ (default: BBS.config.port) on
  # all interfaces and serves callers until the process is interrupted.
  # Blocks; returns +nil+ after Ctrl-C.
  def self.start(port: config.port)
    Server.new(port: port).run
  end

  # Writes one line to the log (stderr): the board's
  # <tt>BBS.config.log_tag</tt>, +tag+ (what the line is about) and
  # +message+, a String or an exception (its class and message).
  #
  #   BBS.log('catalog refresh', error)   # "feedia-bbs: catalog refresh: SocketError: …"
  #
  # Returns +nil+.
  def self.log(tag, message)
    message = "#{message.class}: #{message.message}" if message.is_a?(Exception)
    warn "#{config.log_tag}: #{tag}: #{message}"
  end

  # Runs the block in a BBS::Background thread named +name+ and returns the
  # Thread. An error is logged with BBS.log and the block run again after
  # +retry_after+ seconds, doubled after each failure up to +max_retry+.
  #
  # [every]       +nil+ (the default) runs the block until it succeeds once;
  #               a number of seconds runs it forever, that long apart
  # [retry_after] seconds before the first retry (Background::RETRY_AFTER)
  # [max_retry]   the longest pause between retries (Background::MAX_RETRY)
  #
  #   BBS.background('catalog refresh', every: 3600) { library.refresh }
  def self.background(name, every: nil, retry_after: Background::RETRY_AFTER, max_retry: Background::MAX_RETRY, &)
    Background.new(name, every: every, retry_after: retry_after, max_retry: max_retry, &).start
  end
end
