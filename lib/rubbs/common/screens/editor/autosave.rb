# frozen_string_literal: true

module Rubbs
  module Common
    module Screens
      class Editor
        # The autosave of an Editor: the text handed to the caller's block every
        # few seconds while it changes, and the keys read with a timeout for it
        # (see Editor.new).
        module Autosave
          private

          def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          def start_clock
            @due      = now + @autosave if @autosave
            @last_key = now
          end

          # The next key. An autosaving editor waits at most until the next
          # autosave, which it makes meanwhile, and keeps the idle limit.
          def next_key
            return @screen.key unless @autosave

            loop do
              left = idle_limit - (now - @last_key)
              raise IO::TimeoutError, 'the caller was idle' if left <= 0

              key = @screen.key(timeout: [@due - now, left].min.clamp(0.01, nil))
              if key == :idle
                autosave if due?
                next
              end
              @last_key = now
              return key
            end
          end

          def idle_limit = (@session.idle_seconds if @session.respond_to?(:idle_seconds)) || Line::Server::DEFAULT_TIMEOUT

          def due? = @autosave && now >= @due

          # Hands the text to the block when it changed since the last time.
          def autosave
            return unless @autosave

            @due = now + @autosave
            text = @buffer.text
            return if text == @saved_text

            @saved_text = text
            @on_autosave.call(text)
          rescue StandardError => e
            Rubbs.log('editor autosave', e)
          end
        end
      end
    end
  end
end
