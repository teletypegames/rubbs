# frozen_string_literal: true

module BBS
  class Application
    # What BBS::Session#announce tells the caller of a running Application
    # (the server's shutdown notice): it waits in a queue until the event
    # loop's next turn shows it in a message box.
    module Announcements
      private

      # What BBS::Session#announce tells the caller waits in a queue until
      # the loop's next turn shows it in a message box.
      def listen_announcements
        return unless @session.respond_to?(:on_announce)

        @announcements = Thread::Queue.new
        @session.on_announce(->(text) { @announcements << text })
      end

      def show_announcements
        return unless @announcements

        Dialogs.message(self, @announcements.pop, title: 'Notice') until @announcements.empty?
      end
    end
  end
end
