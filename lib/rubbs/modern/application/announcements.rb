# frozen_string_literal: true

module Rubbs
  module Modern
    class Application
      # What Rubbs::Common::Line::Session#announce tells the caller of a running Application
      # (the server's shutdown notice): it waits in a queue until the event
      # loop's next turn shows it in a message box.
      module Announcements
        private

        # What Rubbs::Common::Line::Session#announce tells the caller waits in a queue until
        # the loop's next turn shows it in a message box.
        def listen_announcements
          return unless @session.respond_to?(:on_announce)

          @announcements = Thread::Queue.new
          @session.on_announce(->(text) { @announcements << text })
        end

        # Shows what waits in a message box each: the announcements, then the
        # notices the line keeps (Rubbs::Common::Line::Notices#take_notices).
        def show_announcements
          Dialogs.message(self, @announcements.pop, title: 'Notice') until @announcements.nil? || @announcements.empty?
          return unless @session.respond_to?(:take_notices)

          @session.take_notices.each { |n| Dialogs.message(self, n.text, title: n.title) }
        end
      end
    end
  end
end
