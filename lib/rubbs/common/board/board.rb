# frozen_string_literal: true

module Rubbs
  module Common
    module Board
      # What Rubbs.board declares, and how it is wired: the configuration derived
      # from the title, the domain object, and the flow of each face.
      #
      # From the title +Feedia BBS+ come the log tag +feedia-bbs+ and the
      # environment prefix +FEEDIA_BBS_+ (Rubbs::Common::Board::Domain#setting). A board with
      # two faces asks the caller's terminal first (Rubbs::Common::Call::Terminal), with one it
      # goes straight to it. A face is
      #
      # - a Rubbs::Modern::Application definition (Application.define): the windowed face,
      #   with the domain's +services+ when it names none
      # - a Rubbs::Petscii::Face subclass (or any class made with the session,
      #   the context and the domain object, that has a +run+): the
      #   line-by-line face, a Rubbs::Common::Screens::Pages
      # - a Rubbs::Common::Call::Flow: run as is
      # - a block: a Flow defined by it, called with the domain object, for what
      #   comes before the face (<tt>big_banner …; app UI::Modern</tt>)
      #
      # and gets the goodbye screen after it (#goodbye).
      class BoardDefinition
        include CentralWiring

        # Idle seconds before a quiet caller is dropped, unless #idle says.
        IDLE = 600

        # The title, the technical name and the domain object (after #configure).
        attr_reader :title, :slug, :board

        # Records the declaration of the block. See Rubbs.board.
        def initialize(title, domain = nil, slug: nil, &block)
          @title     = title
          @slug      = slug || self.class.slug(title)
          @domain    = domain
          @faces     = {}
          @preset    = Preset::NONE
          @idle      = IDLE
          @mouse     = true
          @goodbye   = true
          @note      = nil
          @on_start  = []
          @on_stop   = []
          @on_end    = nil
          @auth      = nil
          @own_goodbye = []
          instance_eval(&block) if block
        end

        # The technical name of +title+: lower case, words joined by dashes.
        #
        #   BoardDefinition.slug('TTG Blog BBS')  # => "ttg-blog-bbs"
        def self.slug(title) = title.downcase.scan(/[a-z0-9]+/).join('-')

        # The board's Rubbs::Common::Board::Preset (splash, goodbye address and QR code,
        # User-Agent).
        def preset(preset) = (@preset = preset)

        # The face of a modern terminal (see the class comment). <tt>goodbye:
        # false</tt> when the face says goodbye its own way.
        def modern(face = nil, goodbye: true, &block)
          @faces[:modern] = block || face
          @own_goodbye << :modern unless goodbye
        end

        # The face of a Commodore 64 (see the class comment). <tt>goodbye:
        # false</tt> when the face says goodbye its own way.
        def petscii(face = nil, goodbye: true, &block)
          @faces[:petscii] = block || face
          @own_goodbye << :petscii unless goodbye
        end

        # The board's own line on the goodbye screen (its sources, licence), or
        # a block given the call's context for a line of each call; +options+
        # are those of Rubbs::Common::Call::Goodbye.show (+clear+, +color+, +bar+, +art+).
        # <tt>goodbye false</tt> leaves the goodbye to the faces.
        def goodbye(note = nil, **options, &dynamic)
          @goodbye = note != false
          @note    = dynamic || note || nil
          @goodbye_options = options
        end

        # Idle seconds before a quiet caller is dropped (default IDLE); a block
        # is given the domain object at boot (<tt>idle { |bbs| bbs.idle_seconds }</tt>).
        def idle(seconds = nil, &block) = (@idle = block || seconds)

        # How callers log in (Rubbs::Common::Auth): +directory+ (a Rubbs::Common::Auth::Directory
        # or Remote, or a block given the domain object at boot), +login+
        # (+:call+ asks at the start of a call, before the face; +:menu+ leaves
        # it to the faces' login item; +:both+) and +guests+ (whether a caller
        # without an account comes in at a +:call+ login).
        #
        # Without a +directory+ the accounts are the Central's (#central).
        #
        #   auth login: :menu                                 # the Central's accounts
        #   auth(login: :call) { |board| board.directory }   # the Central itself
        def auth(directory = nil, login: :menu, guests: true, &block)
          raise ArgumentError, "login: is one of #{Auth::LOGINS.join(', ')}" unless Auth::LOGINS.include?(login)

          @auth = [block || directory, login, guests]
        end

        # Whether the modern face uses the mouse (default +true+).
        def mouse(on) = (@mouse = on)

        # A block run once at boot with the domain object, after its +start+:
        # an HTTP API beside the telnet port, say.
        def on_start(&block) = @on_start << block

        # A block run once with the domain object when the server has stopped,
        # after the last caller and before the domain's own +stop+: an HTTP
        # API beside the telnet port shut, say.
        def on_stop(&block) = @on_stop << block

        # A block run after each call with the session and the domain object
        # (Rubbs::Common::Board::Config#on_session_end).
        def on_session_end(&block) = (@on_end = block)

        # Applies the declaration: Rubbs.config, the domain object (made, then
        # started when it has a +start+), the #on_start blocks and the flow.
        # Returns +self+.
        def configure
          configure_names
          @board = @domain&.new
          Rubbs.config.board = @board
          @board.start if @board.respond_to?(:start)
          @on_start.each { |hook| hook.call(@board) }
          configure_central_client
          configure_auth
          configure_central_server
          configure_badges
          configure_line
          Rubbs.config.flow = flow
          self
        end

        # #configure, then Rubbs.start; when the server has stopped (SIGTERM,
        # Ctrl-C, see Rubbs::Common::Line::Server#stop), #stop. Does not return while the
        # server runs; returns +self+ after.
        #
        #   board = Rubbs.board('Feedia BBS', FeediaBBS) { … }
        #   board.run! if Rubbs.main?(__FILE__)
        def run!
          configure
          Rubbs.start
          self
        ensure
          stop
        end

        # Ends the board after the server: the #on_stop blocks, then the domain
        # object's +stop+ (Rubbs::Common::Board::Domain#stop). An error is logged, not raised.
        # Returns +nil+.
        def stop
          @on_stop.each { |hook| hook.call(@board) }
          Rubbs.config.central&.server&.stop
          @board.stop if @board.respond_to?(:stop)
          nil
        rescue StandardError => e
          Rubbs.log('stop', e)
        end

        # The root flow: the terminal question with two faces, the one face's
        # flow with one.
        def flow
          faces = @faces.to_h { |name, face| [name, face_flow(face, @goodbye && !@own_goodbye.include?(name))] }
          return Call::Terminal.only(*faces.first) if faces.size == 1

          Call::Terminal.flow(title: @title, modern: faces.fetch(:modern), petscii: faces.fetch(:petscii), splash: @preset.splash)
        end

        private

        def configure_names
          config = Rubbs.config
          config.title      = @title
          config.log_tag    = @slug
          config.env_prefix = "#{@slug.upcase.tr('-', '_')}_"
          config.preset     = @preset
        end

        def configure_line
          config = Rubbs.config
          config.idle_seconds     = @idle.respond_to?(:call) ? @idle.call(@board) : @idle
          config.mouse            = @mouse && @faces.key?(:modern)
          config.mouse_on_connect = !@faces.key?(:petscii)
          board = @board
          config.on_session_end = ->(session) { @on_end.call(session, board) } if @on_end
          config.health = -> { board.health } if board.respond_to?(:health)
        end

        def face_flow(face, says_goodbye)
          steps    = face_steps(face)
          asks     = Rubbs.config.auth&.at_call?
          farewell = goodbye_step if says_goodbye
          return steps unless farewell || asks

          Call::Flow.define do
            login if asks
            flow steps
            instance_exec(&farewell) if farewell
          end
        end

        # The goodbye step of the board's note, as a block for a Flow.define.
        def goodbye_step
          note    = @note
          options = @goodbye_options || {}
          proc { note.respond_to?(:call) ? goodbye(**options, &note) : goodbye(note, **options) }
        end

        def face_steps(face)
          board = @board
          case face
          when Call::Flow then face
          when Proc then Call::Flow.define { instance_exec(board, &face) }
          else Call::Flow.define { face.is_a?(Class) ? face(face) : app(face) }
          end
        end
      end
    end
  end
end
