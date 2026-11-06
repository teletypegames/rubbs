# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'

module Rubbs
  class MultiRunner
    # The state file of a Rubbs::MultiRunner, <tt><state>/multi_runner.json</tt>,
    # written whole (a new file renamed over the old) every few seconds: when,
    # the supervisor's pid, the deploy revision, whether a deploy is copying
    # now, and every board's Child#to_h. Monitoring reads it (the boards'
    # health, callers, memory, restarts and revision), and a container's
    # health check its age.
    module Status
      # Writes the state of +children+ into the folder +dir+, with the deploy
      # +revision+ and whether a deploy is +deploying+. Returns the path.
      def self.write(dir, children, revision:, deploying:)
        FileUtils.mkdir_p(dir)
        path = File.join(dir, STATUS_FILE)
        data = {
          time:      Time.now.utc.iso8601,
          pid:       Process.pid,
          revision:  revision,
          deploying: deploying,
          boards:    children.map(&:to_h)
        }
        File.write("#{path}.tmp", "#{JSON.pretty_generate(data)}\n")
        File.rename("#{path}.tmp", path)
        path
      end

      # The state written in the folder +dir+ (a Hash), or +nil+ without one.
      def self.read(dir)
        JSON.parse(File.read(File.join(dir, STATUS_FILE)))
      rescue SystemCallError, JSON::ParserError
        nil
      end

      # Whether the state in +dir+ was written in the last +seconds+: what a
      # container's health check asks
      # (<tt>ruby -rrubbs -e 'exit Rubbs::MultiRunner::Status.fresh?("state")'</tt>).
      def self.fresh?(dir, seconds = 90)
        Time.now - File.mtime(File.join(dir, STATUS_FILE)) < seconds
      rescue SystemCallError
        false
      end
    end
  end
end
