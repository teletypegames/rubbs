# frozen_string_literal: true

module Rubbs
  module Common
    module Auth
      class Profile
        # What the head of a profile says, for the face that draws it: the
        # title, who is on the line, their roles or a guest's note.
        module Head
          # The lines of the head for a face to draw (Rubbs::Modern::Profile,
          # Rubbs::Petscii::Profile), [text, role] each: the title (+:title+),
          # who is on the line (+:text+), and their roles or a guest's note
          # (+:dim+).
          def head_lines
            [[@look.title, :title], *status.each_with_index.map { |text, i| [text, i.zero? ? :text : :dim] }]
          end

          private

          # Who is on the line, a line; and their roles (or a guest's note), a
          # line or none.
          def status
            return [@words[:guest], @look.note].compact unless identity.signed_in?

            [format(@words[:signed_in], name: identity.name), format(@words[:roles], roles: identity.roles.join(', '))]
          end
        end
      end
    end
  end
end
