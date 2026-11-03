# frozen_string_literal: true

module BBS
  # Declares the board and starts it: the one call of a board's +bbs.rb+.
  #
  #   BBS.board 'Alexandria BBS', AlexandriaBBS do
  #     preset  TTG::PRESET
  #     modern  UI::Modern
  #     petscii UI::Petscii
  #     goodbye 'Articles from wikipedia.org, under CC BY-SA.'
  #   end
  #
  # [title]  the board's name as callers read it
  # [domain] the class of the board's domain object (usually a
  #          BBS::Domain), made once at boot, or +nil+
  # [slug]   the technical name, when it is not the title's
  #          (<tt>'WarpEngine BBS'</tt> → <tt>warp-engine-bbs</tt>)
  #
  # The block is evaluated in a BBS::BoardDefinition. Does not return
  # while the server runs.
  def self.board(title, domain = nil, slug: nil, &)
    BoardDefinition.new(title, domain, slug: slug, &).start
  end

  # What BBS.board declares, and how it is wired: the configuration derived
  # from the title, the domain object, and the flow of each face.
  #
  # From the title +Feedia BBS+ come the log tag +feedia-bbs+ and the
  # environment prefix +FEEDIA_BBS_+ (BBS::Domain#setting). A board with
  # two faces asks the caller's terminal first (BBS::Terminal), with one it
  # goes straight to it. A face is
  #
  # - a BBS::Application definition (Application.define): the windowed face,
  #   with the domain's +services+ when it names none
  # - a BBS::Petscii::Face subclass (or any class made with the session,
  #   the context and the domain object, that has a +run+): the
  #   line-by-line face, a BBS::Pages
  # - a BBS::Flow: run as is
  # - a block: a Flow defined by it, called with the domain object, for what
  #   comes before the face (<tt>big_banner …; app UI::Modern</tt>)
  #
  # and gets the goodbye screen after it (#goodbye).
  class BoardDefinition
    # Idle seconds before a quiet caller is dropped, unless #idle says.
    IDLE = 600

    # The title, the technical name and the domain object (after #configure).
    attr_reader :title, :slug, :board

    # Records the declaration of the block. See BBS.board.
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
      @on_end    = nil
      @own_goodbye = []
      instance_eval(&block) if block
    end

    # The technical name of +title+: lower case, words joined by dashes.
    #
    #   BoardDefinition.slug('TTG Blog BBS')  # => "ttg-blog-bbs"
    def self.slug(title) = title.downcase.scan(/[a-z0-9]+/).join('-')

    # The board's BBS::Preset (splash, goodbye address and QR code,
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
    # are those of BBS::Goodbye.show (+clear+, +color+, +bar+, +art+).
    # <tt>goodbye false</tt> leaves the goodbye to the faces.
    def goodbye(note = nil, **options, &dynamic)
      @goodbye = note != false
      @note    = dynamic || note || nil
      @goodbye_options = options
    end

    # Idle seconds before a quiet caller is dropped (default IDLE); a block
    # is given the domain object at boot (<tt>idle { |bbs| bbs.idle_seconds }</tt>).
    def idle(seconds = nil, &block) = (@idle = block || seconds)

    # Whether the modern face uses the mouse (default +true+).
    def mouse(on) = (@mouse = on)

    # A block run once at boot with the domain object, after its +start+:
    # an HTTP API beside the telnet port, say.
    def on_start(&block) = @on_start << block

    # A block run after each call with the session and the domain object
    # (BBS::Config#on_session_end).
    def on_session_end(&block) = (@on_end = block)

    # Applies the declaration: BBS.config, the domain object (made, then
    # started when it has a +start+), the #on_start blocks and the flow.
    # Returns +self+.
    def configure
      configure_names
      @board = @domain&.new
      BBS.config.board = @board
      @board.start if @board.respond_to?(:start)
      @on_start.each { |hook| hook.call(@board) }
      configure_line
      BBS.config.flow = flow
      self
    end

    # #configure, then BBS.start. Does not return while the server runs.
    def start
      configure
      BBS.start
    end

    # The root flow: the terminal question with two faces, the one face's
    # flow with one.
    def flow
      faces = @faces.to_h { |name, face| [name, face_flow(face, @goodbye && !@own_goodbye.include?(name))] }
      return faces.values.first if faces.size == 1

      Terminal.flow(title: @title, modern: faces.fetch(:modern), petscii: faces.fetch(:petscii), splash: @preset.splash)
    end

    private

    def configure_names
      config = BBS.config
      config.title      = @title
      config.log_tag    = @slug
      config.env_prefix = "#{@slug.upcase.tr('-', '_')}_"
      config.preset     = @preset
    end

    def configure_line
      config = BBS.config
      config.idle_seconds     = @idle.respond_to?(:call) ? @idle.call(@board) : @idle
      config.mouse            = @mouse && @faces.key?(:modern)
      config.mouse_on_connect = !@faces.key?(:petscii)
      board = @board
      config.on_session_end = ->(session) { @on_end.call(session, board) } if @on_end
    end

    def face_flow(face, goodbye)
      board = @board
      steps = case face
              when Flow then face
              when Proc then Flow.define { instance_exec(board, &face) }
              else Flow.define { face.is_a?(Class) ? face(face) : app(face) }
              end
      note    = @note
      options = @goodbye_options || {}
      return steps unless goodbye

      Flow.define do
        flow steps
        note.respond_to?(:call) ? goodbye(**options, &note) : goodbye(note, **options)
      end
    end
  end
end
