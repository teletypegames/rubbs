# frozen_string_literal: true

module BBS
  # Where the blocks of a BBS::WindowSpec run: the application (its
  # helpers, services and methods are called as if from inside it), the
  # +extras+ the window was opened with as methods, and the window itself.
  #
  #   show :article, article: found        # in the spec: title { article.title }
  #
  # An extra may not share its name with a method of the application:
  # Application#show raises ArgumentError for it, so a helper never hides
  # an extra or the other way round.
  class WindowContext
    # The window, once open (+nil+ while its attributes are resolved).
    attr_accessor :window

    # Whether a button's or a form's block called #keep.
    attr_accessor :kept

    # The application and the extras of the window. Raises ArgumentError
    # when an extra is named like a method of +app+.
    def initialize(app, extras)
      clash = extras.keys.select { |key| app.respond_to?(key) }
      raise ArgumentError, "window extras named like application methods: #{clash.inspect}" unless clash.empty?

      @app    = app
      @extras = extras
      @kept   = false
    end

    # The application.
    attr_reader :app

    # The window's extras, a Hash.
    attr_reader :extras

    # Closes the window.
    def close = @app.close_window(@window)

    # Keeps an info window or a form open after its button's block.
    def keep = (@kept = true)

    # Refuses a form's submission: shows +message+ in the form and keeps it
    # open. Raises WindowSpec::Refused (caught by the form).
    def error!(message) = raise(WindowSpec::Refused, message)

    # The form whose +on_submit+ runs (the window).
    def form = @window

    # The selected item of a master/detail window, or +nil+.
    def selected = @window.respond_to?(:list_widget) ? @window.list_widget.selected_item : nil

    # Whether +name+ is an extra or a method of the application.
    def respond_to_missing?(name, include_private = false)
      @extras.key?(name) || @app.respond_to?(name, true) || super
    end

    # An extra by +name+, else the application's method.
    def method_missing(name, *args, **kw, &)
      return @extras[name] if @extras.key?(name) && args.empty? && kw.empty?
      return @app.send(name, *args, **kw, &) if @app.respond_to?(name, true)

      super
    end
  end
end
