# frozen_string_literal: true

module BBS
  # A piece of an Application declaration in a file of its own: a module
  # that extends Part and declares with the same words as
  # Application.define (BBS::Application::Builder::DSL); +parts+ replays
  # them in the application.
  #
  #   module UI::Modern::ArticleWindow
  #     extend BBS::Part
  #
  #     window :article, :master_detail do
  #       title { article.title }
  #       items { article.sections }
  #     end
  #   end
  #
  #   UI::Modern = BBS::Application.define do
  #     parts UI::Modern::ArticleWindow, UI::Modern::Menu
  #   end
  module Part
    Application::Builder::DSL.each do |name|
      define_method(name) do |*args, **kw, &block|
        declarations << [name, args, kw, block]
        nil
      end
    end

    # The declarations recorded so far: <tt>[name, args, keywords, block]</tt>.
    def declarations = @declarations ||= []

    # Replays the declarations on +builder+, an Application::Builder.
    def install(builder)
      declarations.each { |name, args, kw, block| builder.public_send(name, *args, **kw, &block) }
    end
  end
end
