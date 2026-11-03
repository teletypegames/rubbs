# frozen_string_literal: true

module BBS
  # The line dropped: the caller hung up, or the socket broke. An IOError,
  # so every place that already lets an IOError end the call lets this one
  # end it too. rubbs raises it where a read finds no caller; a Flow step,
  # an Application and a Petscii::Face end the call quietly on it, so a
  # board never rescues it.
  class Hangup < IOError
    # Creates the error with +message+.
    def initialize(message = 'the caller hung up') = super
  end

  # The errors that mean the line is gone, for a +rescue+ that has to tell
  # them from a bug: <tt>rescue *BBS::LINE_DROPPED</tt>.
  LINE_DROPPED = [IOError, Errno::EPIPE, Errno::ECONNRESET].freeze

  # Ends the command the caller started (a menu item, a key, a button)
  # without an error: Application#loading raises it after telling the caller
  # what went wrong, Application#fail_with raises it with a message. The
  # application's event loop catches it, the caller stays where they were.
  class Abort < StandardError
  end
end
