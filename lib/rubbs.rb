# frozen_string_literal: true

require_relative 'rubbs/common'
require_relative 'rubbs/modern'
require_relative 'rubbs/common/line/hangup'
require_relative 'rubbs/common/board/preset'
require_relative 'rubbs/modern/ansi'
require_relative 'rubbs/common/line/ascii'
require_relative 'rubbs/common/text'
require_relative 'rubbs/common/line/address'
require_relative 'rubbs/common/text/patterns'
require_relative 'rubbs/common/board/config'
require_relative 'rubbs/common/log'
require_relative 'rubbs/common/line/health'
require_relative 'rubbs/petscii'
require_relative 'rubbs/common/line/telnet'
require_relative 'rubbs/common/screens/text_buffer'
require_relative 'rubbs/common/screens/cursor'
require_relative 'rubbs/common/screens/field'
require_relative 'rubbs/common/screens/selector'
require_relative 'rubbs/common/screens/editor'
require_relative 'rubbs/petscii/colors'
require_relative 'rubbs/petscii/screen'
require_relative 'rubbs/petscii/face'
require_relative 'rubbs/petscii/canvas'
require_relative 'rubbs/petscii/canvas_menu'
require_relative 'rubbs/common/art'
require_relative 'rubbs/common/season'
require_relative 'rubbs/common/text/block_font'
require_relative 'rubbs/common/call/goodbye'
require_relative 'rubbs/common/web/discord_webhook'
require_relative 'rubbs/common/text/banner'
require_relative 'rubbs/common/call/flow'
require_relative 'rubbs/common/call/flow_runner'
require_relative 'rubbs/common/call/splash'
require_relative 'rubbs/common/call/terminal'
require_relative 'rubbs/common/fake_os'
require_relative 'rubbs/common/ai'
require_relative 'rubbs/common/call/door'
require_relative 'rubbs/common/line/gateway'
require_relative 'rubbs/common/line/gateway/ascii_bridge'
require_relative 'rubbs/common/files/zmodem'
require_relative 'rubbs/common/files/xmodem'
require_relative 'rubbs/common/call/renderer'
require_relative 'rubbs/common/storage/database'
require_relative 'rubbs/common/storage/model'
require_relative 'rubbs/common/storage/store'
require_relative 'rubbs/common/web/http'
require_relative 'rubbs/common/storage/cache'
require_relative 'rubbs/common/line/rate_limit'
require_relative 'rubbs/common/board/background'
require_relative 'rubbs/common/central'
require_relative 'rubbs/common/auth'
require_relative 'rubbs/common/web/media_wiki'
require_relative 'rubbs/common/web/media_wiki/extract'
require_relative 'rubbs/common/web/wikipedia'
require_relative 'rubbs/common/web/wikidata'
require_relative 'rubbs/common/text/qr'
require_relative 'rubbs/modern/frame_buffer'
require_relative 'rubbs/modern/style'
require_relative 'rubbs/common/line/nodes'
require_relative 'rubbs/common/screens/pages'
require_relative 'rubbs/common/screens/page'
require_relative 'rubbs/modern/widgets/event'
require_relative 'rubbs/modern/theme'
require_relative 'rubbs/modern/widgets/widget'
require_relative 'rubbs/modern/widgets/container'
require_relative 'rubbs/modern/widgets'
require_relative 'rubbs/modern/widgets/scene'
require_relative 'rubbs/modern/window'
require_relative 'rubbs/modern/widgets/focus_manager'
require_relative 'rubbs/modern/menu'
require_relative 'rubbs/modern/statusbar'
require_relative 'rubbs/modern/dialogs'
require_relative 'rubbs/common/text/markdown'
require_relative 'rubbs/modern/windows/button_bar'
require_relative 'rubbs/modern/windows/info'
require_relative 'rubbs/modern/windows/form'
require_relative 'rubbs/modern/windows/master_detail'
require_relative 'rubbs/modern/windows/stream'
require_relative 'rubbs/modern/application'
require_relative 'rubbs/common/line/session'
require_relative 'rubbs/common/line/server'
require_relative 'rubbs/common/board/domain'
require_relative 'rubbs/common/board/central_wiring'
require_relative 'rubbs/common/board/board'
require_relative 'rubbs/modern/part'
require_relative 'rubbs/common/storage/snapshot'
require_relative 'rubbs/common/files/transfer'
require_relative 'rubbs/petscii/kit'
require_relative 'rubbs/modern/kit'

# The +bbs+ gem: a library for telnet BBS servers. Requiring it loads the
# whole library. Configure it with Rubbs.configure, then start the server with
# Rubbs.start:
#
#   require 'rubbs'
#
#   Rubbs.configure do |c|
#     c.port = 2323
#     c.flow = MY_FLOW
#   end
#   Rubbs.start
#
# See README.md for the guide.
module Rubbs
  # Declares the board and starts it: the one call of a board's +bbs.rb+.
  #
  #   Rubbs.board 'Alexandria BBS', AlexandriaBBS do
  #     preset  TTG::PRESET
  #     modern  UI::Modern
  #     petscii UI::Petscii
  #     goodbye 'Articles from wikipedia.org, under CC BY-SA.'
  #   end
  #
  # [title]  the board's name as callers read it
  # [domain] the class of the board's domain object (usually a
  #          Rubbs::Common::Board::Domain), made once at boot, or +nil+
  # [slug]   the technical name, when it is not the title's
  #          (<tt>'WarpEngine BBS'</tt> → <tt>warp-engine-bbs</tt>)
  #
  # The block is evaluated in a Rubbs::Common::Board::BoardDefinition. Does not return
  # while the server runs.
  def self.board(title, domain = nil, slug: nil, &)
    Common::Board::BoardDefinition.new(title, domain, slug: slug, &).start
  end

  # Yields the global Rubbs::Common::Board::Config (created on first use) so the block can set
  # its fields. Returns the block's value.
  def self.configure = yield(config)

  # The global Rubbs::Common::Board::Config, created with its defaults on first use.
  def self.config
    @config ||= Common::Board::Config.new
  end

  # Starts a Rubbs::Common::Line::Server listening on +port+ (default: Rubbs.config.port) on
  # all interfaces and serves callers until the process is interrupted.
  # Blocks; returns +nil+ after Ctrl-C.
  def self.start(port: config.port)
    Common::Line::Server.new(port: port).run
  end

  # The +service+ of the Central (a Rubbs::Common::Central::Service
  # subclass) as a Rubbs::Common::Central::Proxy: on the Central it runs here, on
  # another board it is asked over HTTP; without a Central (no +central+ in
  # Rubbs.board) every answer is +unavailable+.
  #
  #   Rubbs.central(Wall).post(Rubbs::Common::Central::Actor.of(session), text: 'Hello')
  def self.central(service)
    link = config.central or return Common::Central::Proxy.away(service)
    link.proxy(service)
  end

  # The calls on this board's line now (Rubbs::Common::Line::Server#live of
  # Rubbs::Common::Line::Server.current): Rubbs::Common::Line::Session objects, the earliest first; empty
  # when no server runs in this process.
  #
  #   Rubbs.calls.map { |s| [s.caller_name || 'guest', s.caller_ip, s.place] }
  def self.calls = Common::Line::Server.current&.live || []

  # Writes one line to the log (stderr, Rubbs::Common::Log): the board's
  # <tt>Rubbs.config.log_tag</tt>, +tag+ (what the line is about),
  # +message+ (a String or an exception: its class, message and, at the
  # +:error+ level, its first backtrace lines), the +level+ (+:debug+,
  # +:info+, +:warn+, +:error+, +:fatal+; an exception is +:error+ and a
  # String +:info+ unless given) and +fields+, more facts as keys and
  # values. As text or JSON by <tt>Rubbs.config.log_format</tt>.
  #
  #   Rubbs.log('catalog refresh', error)                              # "feedia-bbs: catalog refresh: SocketError: …"
  #   Rubbs.log('catalog refresh', error, level: :warn, retry_in: 10)
  #   Rubbs.log('index', 'loaded', rfcs: 9700)
  #
  # Returns +nil+.
  def self.log(tag, message, level: nil, **fields) = Common::Log.write(tag, message, level: level, **fields)

  # The version of rubbs running, a String (+"2.8.0"+): the loaded gem's,
  # else the one in the checkout's rubbs.gemspec; +"unknown"+ without either.
  # The +server+ line of a board's start carries it (+rubbs+).
  def self.version
    @version ||= Gem.loaded_specs['rubbs']&.version&.to_s || gemspec_version || 'unknown'
  end

  # The version written in the rubbs.gemspec next to +lib+, or +nil+.
  def self.gemspec_version
    File.read(File.expand_path('../rubbs.gemspec', __dir__))[/\.version\s*=\s*['"]([^'"]+)['"]/, 1]
  rescue SystemCallError
    nil
  end
  private_class_method :gemspec_version

  # +seconds+ as a short duration for a caller: <tt>45s</tt>, <tt>12m</tt>,
  # <tt>2h 5m</tt>. A Time is taken as the start of what lasted until now
  # (<tt>Rubbs.duration(context[:started_at])</tt>).
  def self.duration(seconds)
    seconds = Time.now - seconds if seconds.is_a?(Time)
    seconds = seconds.to_i
    return "#{seconds}s" if seconds < 60
    return "#{seconds / 60}m" if seconds < 3600

    "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
  end

  # Runs the block in a Rubbs::Common::Board::Background thread named +name+ and returns the
  # Thread. An error is logged with Rubbs.log and the block run again after
  # +retry_after+ seconds, doubled after each failure up to +max_retry+.
  #
  # [every]       +nil+ (the default) runs the block until it succeeds once;
  #               a number of seconds runs it forever, that long apart
  # [retry_after] seconds before the first retry (Background::RETRY_AFTER)
  # [max_retry]   the longest pause between retries (Background::MAX_RETRY)
  #
  #   Rubbs.background('catalog refresh', every: 3600) { library.refresh }
  def self.background(
    name,
    every: nil,
    retry_after: Common::Board::Background::RETRY_AFTER,
    max_retry: Common::Board::Background::MAX_RETRY,
    &
  )
    Common::Board::Background.new(name, every: every, retry_after: retry_after, max_retry: max_retry, &).start
  end
end

# The faces of the two-faced screens: how each draws a Rubbs::Common::Art, a
# splash, a goodbye and the head of a profile.
require_relative 'rubbs/modern/art'
require_relative 'rubbs/modern/goodbye'
require_relative 'rubbs/modern/profile'
require_relative 'rubbs/modern/splash'
require_relative 'rubbs/petscii/art'
require_relative 'rubbs/petscii/goodbye'
require_relative 'rubbs/petscii/profile'
require_relative 'rubbs/petscii/splash'
