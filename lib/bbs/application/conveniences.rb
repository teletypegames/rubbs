# frozen_string_literal: true

module BBS
  class Application
    # What a board's helpers and window blocks call on the application: the
    # dialogs, a wait box, a QR code, the windows by name.
    module Conveniences
      # Columns the "Please wait" box takes beside its text.
      LOADING_CHROME = 8
      # Columns and rows a QR window takes beside its code.
      QR_CHROME = [4, 7].freeze
      # The padding of a QR window.
      QR_PADDING = { sides: 2, top: 1, bottom: 0 }.freeze

      # Opens a message box with +text+ and OK. Returns the Window.
      def message(text, title: 'Message', width: nil) = Dialogs.message(self, text, title: title, width: width)

      # Opens a box asking for a line of text; OK (or Enter) runs the block
      # with what was typed, unless it is blank. Returns the Window.
      #
      #   ask 'Article title:', title: 'Search' do |text| look_up(text) end
      def ask(prompt, title: 'Input', value: '', width: Dialogs::INPUT_WIDTH, &on_submit)
        Dialogs.input(
          self,
          prompt:    prompt,
          title:     title,
          value:     value,
          width:     width,
          on_submit: ->(text) { instance_exec(text, &on_submit) unless text.strip.empty? }
        )
      end

      # Opens a Yes/No box; Yes runs the block. Returns the Window.
      def confirm(text, title: 'Confirm', &on_yes)
        Dialogs.confirm(self, text, title: title, on_yes: -> { instance_exec(&on_yes) if on_yes })
      end

      # Runs the block in a thread under a "Please wait" box with +text+ and
      # returns its value. With +failed+, a +nil+ value or an error is told
      # to the caller as +failed+ (a message box) and ends the command
      # (raises BBS::Abort, which the event loop takes quietly), in a box
      # titled +title+; without it
      # the value is returned as it is and an error is raised.
      #
      #   article = loading('Loading the article…', failed: NO_ANSWER) { articles.article(title) }
      def loading(text = 'Working…', failed: nil, title: 'Sorry', &)
        value = in_thread(text, &)
        fail_with(failed, title: title) if failed && value.nil?
        value
      rescue Abort, *LINE_DROPPED
        raise
      rescue StandardError => e
        raise unless failed

        BBS.log('loading', e)
        fail_with(failed, title: title)
      end

      # Tells the caller what +result+ (a Symbol a domain service answered)
      # means: its text in +messages+ in a message box, when there is one.
      # Returns +result+.
      #
      #   report(posts.add(text), Wording::POST, title: 'Post')
      def report(result, messages, title: 'Message')
        text = messages[result]
        message(text, title: title) if text
        result
      end

      # Tells the caller +text+ in a message box and ends the command
      # (raises BBS::Abort).
      def fail_with(text, title: 'Sorry')
        message(text, title: title)
        raise Abort, text
      end

      # Shows +text+ (an address) as a QR code in a window as big as the
      # screen allows: with a quiet zone when it fits, without one when only
      # that fits, else a message saying the screen is too small. Returns
      # the Window.
      def qr(text, title: 'QR code')
        code = qr_code(text) or return message('The screen is too small for this QR code.', title: title)
        Windows::Info.open(
          self,
          title:   title,
          body:    code,
          padding: QR_PADDING,
          width:   FrameBuffer.visible_width(code.first) + QR_CHROME[0]
        )
      end

      # Opens the declared window +name+ with +extras+ (see BBS::WindowSpec),
      # or pushes +name+ when it is a BBS::Window. Returns the window.
      def show(name, **extras) = open_window(name, **extras)

      # The open window declared as +name+ (the frontmost one), or +nil+.
      def window(name) = @windows.reverse.find { |w| w.id == name.to_sym }

      # Closes every window.
      def close_all
        close_window while top_window
      end

      # Redraws the detail pane of every open master/detail window (after
      # the data under them changed).
      def reload_details
        @windows.grep(Windows::MasterDetail).each { |w| w.reload_detail(keep_scroll: true) }
      end

      # +text+ (Markdown) as lines +width+ columns wide in the theme's
      # colours (BBS::Markdown).
      def markdown(text, width = cols - 4) = Markdown.to_lines(text, width: width, theme: theme)

      # The key the caller is known by for rate limits
      # (BBS::Session#caller_key).
      def caller_key = @session.caller_key

      # Opens the login box of the board's BBS::Auth::Setup: name and
      # password; a good pair makes the caller that account (see
      # BBS::Auth::Conveniences#identity), a wrong one is said in the box.
      # Then the block, when given, runs in the application with the
      # Identity (to say more than "Welcome", or to show what the account
      # may now see); without one the caller is welcomed. Returns the window.
      #
      #   command(:log_in, 'Log in…') { log_in { |who| message('Not an editor.') unless who.role?(:blogger) } }
      def log_in(title: 'Log in', &after)
        setup = auth_setup or return message(no_login)
        Windows::Form.open(
          self,
          title:        title,
          width:        52,
          submit_label: '&Log in',
          fields:       [
            { key: :name, label: 'Name', max_length: 20 },
            { key: :password, label: 'Password', password: true, max_length: 200 }
          ],
          on_submit:    ->(values, form) { submit_login(setup, values, form, after) }
        )
      end

      # The caller's profile (BBS::Auth::Profile) on the bare line, then the
      # whole screen again. Returns +nil+.
      def open_profile
        with_line { Auth::Profile.run(@session) }
        nil
      end

      # Logs the caller out (BBS::Auth::Conveniences#log_out) and says so.
      def log_out_now
        log_out
        message('You are logged out.', title: 'Log out')
      end

      private

      def submit_login(setup, values, form, after = nil)
        result = setup.directory.log_in(values[:name].to_s.strip, values[:password].to_s, caller_key: caller_key)
        unless result.is_a?(Auth::Identity)
          form.error(Auth::Login::WORDS.fetch(result, Auth::Login::WORDS[:wrong]))
          return :keep
        end

        @session.identity = result
        after ? instance_exec(result, &after) : message("Welcome, #{result.name}.", title: 'Log in')
        :close
      end

      def qr_code(text)
        room = { width: cols - QR_CHROME[0], height: rows - QR_CHROME[1] }
        QR.ansi(text, **room)
      rescue QR::TooLong
        begin
          QR.ansi(text, **room, quiet: 1)
        rescue QR::TooLong
          nil
        end
      end

      def in_thread(text, &block)
        box = message(text, title: 'Please wait', width: text.length + LOADING_CHROME)
        render_screen
        result = nil
        error  = nil
        Thread.new do
          result = block.call
        rescue StandardError => e
          error = e
        ensure
          close_window(box)
        end.join
        raise error if error

        result
      end
    end
  end
end
