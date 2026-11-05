# frozen_string_literal: true

module Rubbs
  module Common
    module Screens
      # Colours by role, the same words on both faces: a piece of text in a
      # role, back to the plain text colour after it. An Application paints
      # with its Rubbs::Modern::Theme, a Rubbs::Petscii::Face with the C64 palette
      # (Petscii::Face::ROLES), so a line built with these reads the same on
      # either.
      #
      #   "#{bright(book.title)} #{dim(book.year)}"
      #   paint(:error, 'Wikipedia did not answer.')
      #
      # The includer answers +paint_style(role)+ (the SGR of +role+) and
      # +paint_reset+ (the SGR of plain text).
      module Paint
        # +text+ in the colour of +role+ (+:text_dim+, +:text_bright+,
        # +:accent+, +:label+, +:error+, +:success+ …), then the plain colour.
        def paint(role, text) = "#{paint_style(role)}#{text}#{paint_reset}"

        # +text+ dimmed.
        def dim(text) = paint(:text_dim, text)

        # +text+ bright.
        def bright(text) = paint(:text_bright, text)

        # +text+ in the accent colour.
        def accent(text) = paint(:accent, text)

        private

        def paint_style(role) = theme[role] || theme[:text]

        def paint_reset = theme[:text]
      end
    end
  end
end
