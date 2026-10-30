# frozen_string_literal: true

module BBS
  # Runs a BBS::Flow on a session: walks its steps in order (screens,
  # banners, prompts, menus, blocks, nested TUI, Application and FakeOS
  # programs), writing to and reading from the caller's line, with a context
  # Hash that +ask+, +set+, +fetch+ and +pick+ steps fill and later steps
  # and blocks read.
  #
  #   BBS::FlowRunner.new(session, session_id, flow, context: { name: 'Zsolt' }).run
  #
  # An error raised in a block step is reported to the caller and on stderr
  # and the flow carries on; a dropped line (IOError, EPIPE, ECONNRESET)
  # ends it.
  class FlowRunner
    # Named colours for the +style+ and +color+ options of the steps: style
    # Symbol => SGR String. An unknown name falls back to +:muted+ (or
    # +:success+ for banners).
    STYLES = {
      success: Ansi::BRIGHT_GREEN,
      muted:   Ansi::GREY,
      error:   Ansi::BRIGHT_RED,
      info:    Ansi::YELLOW,
      prompt:  Ansi::WHITE,
      confirm: Ansi::BRIGHT_CYAN,
      cyan:    Ansi::CYAN,
      magenta: Ansi::MAGENTA,
      blue:    Ansi::BLUE,
      yellow:  Ansi::YELLOW,
      white:   Ansi::WHITE,
      green:   Ansi::BRIGHT_GREEN,
      red:     Ansi::BRIGHT_RED,
    }.freeze

    # Moves the cursor up a line and erases that line: takes back the
    # loading message of a +fetch+ step.
    ERASE_LINE_ABOVE = "\e[1A\e[2K"
    # An answer to a +pick+ step: digits only.
    NUMBER = /\A\d+\z/
    # An address the +:email+ validator accepts: something, an @, and a
    # domain with a dot.
    EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    # The caller's session ID and the BBS::Session the flow runs on.
    attr_reader :session_id, :session

    # Creates a runner for +flow+ (a BBS::Flow) on +session+. +context+
    # seeds the flow's context, such as the caller's name when a flow runs
    # as a door; +session_id+ is stored in it under +:session_id+.
    def initialize(session, session_id, flow, context: {})
      @session    = session
      @session_id = session_id
      @flow       = flow
      @ctx        = { **context, session_id: session_id }
    end

    # Runs the flow's steps until they end or one stops the flow. Returns
    # +:halt+ when the flow was stopped (a hang-up, a failed +ask+ or +gate+,
    # a refused confirmation, a block returning +:halt+), +:exit_menu+ when
    # an +exit_menu+ step ran outside a menu, +nil+ otherwise.
    def run
      execute(@flow.steps)
    end

    # Writes +data+ to the caller's line. Blocks of +call+ steps get the
    # runner as their second argument to write with.
    def write(data) = @session.write(data)
    # Reads a line from the caller, echoing +mask+ in place of each
    # character when given. Returns the line, or +nil+ when the caller hung
    # up.
    def readline(mask: nil) = @session.readline(mask: mask)

    private

    def field(prompt)
      Field.ask(@session, prompt).to_s.strip
    rescue IOError
      nil
    end

    def execute(steps)
      steps.each do |step|
        result = dispatch(step)
        return result if result == :halt || result == :exit_menu
      end
      nil
    end

    def dispatch(step)
      case step[:type]
      when :screen        then run_screen(step)
      when :banner        then run_banner(step)
      when :big_banner    then run_big_banner(step)
      when :say           then run_say(step)
      when :set           then run_set(step)
      when :ask           then run_ask(step)
      when :persist       then run_persist(step)
      when :pause         then run_pause(step)
      when :gate          then run_gate(step)
      when :confirm_halt  then run_confirm_halt(step)
      when :confirm_block then run_confirm_block(step)
      when :menu          then run_menu(step)
      when :exit_menu     then :exit_menu
      when :call          then run_call(step)
      when :line          then run_line(step)
      when :section       then run_section(step)
      when :text          then run_text(step)
      when :rows          then run_rows(step)
      when :table         then run_table(step)
      when :wait_enter    then run_wait_enter(step)
      when :fetch         then run_fetch(step)
      when :pick          then run_pick(step)
      when :body          then run_body(step)
      when :output        then run_output(step)
      when :tui           then run_tui(step)
      when :app           then run_app(step)
      when :os            then run_os(step)
      end
    end

    # ── step handlers ──────────────────────────────────────────────────────────

    def run_screen(step)
      vars = step[:vars].transform_values { |v| v.is_a?(Symbol) ? @ctx[v] : v }
      dir  = @flow.screens_dir || BBS.config.screens_dir
      write Renderer.render(step[:name].to_s, @ctx.merge(vars), dir: dir)
    end

    def run_banner(step)
      color = STYLES.fetch(step[:style], STYLES[:success])
      write Banner.render(step[:text], color: color)
    end

    def run_big_banner(step)
      color = STYLES.fetch(step[:style], STYLES[:success])
      write Banner.render_big(step[:text], color: color, font: step[:font])
    end

    def run_say(step)
      color = STYLES.fetch(step[:style], STYLES[:muted])
      write "#{Ansi::CRLF}  #{color}#{step[:text]}#{Ansi::RESET}#{Ansi::CRLF * 2}"
    end

    def run_set(step)
      @ctx[step[:name]] = step[:value]
      nil
    end

    # On a C64 the answer is typed in a BBS::Field, which edits with the
    # cursor keys; a cancelled field is an empty answer.
    def run_ask(step)
      prompt = "  #{STYLES[:prompt]}#{step[:prompt]}#{Ansi::RESET}: "
      value  = if @session.respond_to?(:petscii?) && @session.petscii?
                 field(prompt)
               else
                 write prompt
                 readline&.strip
               end
      return :halt if value.nil?

      value = apply_transform(value, step[:transform])

      if step[:validate] && !valid?(value, step[:validate])
        write "#{Ansi::CRLF}  #{STYLES[:error]}#{validation_message(step[:validate])}#{Ansi::RESET}#{Ansi::CRLF * 2}"
        return :halt
      end

      @ctx[step[:name]] = value
      nil
    end

    def run_persist(step)
      fields = step[:fields].filter_map { |f| [f, @ctx[f]] if @ctx.key?(f) }.to_h
      step[:store].upsert(session_id: @session_id, **fields) unless fields.empty?
      nil
    end

    def run_pause(step)
      write "#{Ansi::CRLF}  #{STYLES[:info]}#{step[:message]}#{Ansi::RESET}#{Ansi::CRLF}"
      sleep step[:seconds]
      nil
    end

    def run_gate(step)
      return nil if step[:check].call(@ctx)
      write "  #{STYLES[:error]}#{step[:denied]}#{Ansi::RESET}#{Ansi::CRLF * 2}"
      :halt
    end

    def run_confirm_halt(step)
      write "#{Ansi::CRLF}  #{STYLES[:confirm]}#{step[:message]}#{Ansi::RESET} [yes/no]: "
      answer = readline&.strip&.downcase
      return :halt if answer.nil?
      return nil   if %w[yes y].include?(answer)
      write "#{Ansi::CRLF}  #{STYLES[:muted]}#{step[:denied]}#{Ansi::RESET}#{Ansi::CRLF * 2}" if step[:denied]
      :halt
    end

    def run_confirm_block(step)
      write "#{Ansi::CRLF}  #{STYLES[:prompt]}#{step[:message]}#{Ansi::RESET} [yes/no]: "
      answer = readline&.strip&.downcase
      return :halt if answer.nil?

      if %w[yes y].include?(answer)
        execute(step[:sub_steps])
      else
        write "#{Ansi::CRLF}  #{STYLES[:muted]}#{step[:denied]}#{Ansi::RESET}#{Ansi::CRLF * 2}" if step[:denied]
        nil
      end
    end

    def run_menu(step)
      loop do
        write Ansi::CRLF
        step[:options].each_with_index do |opt, i|
          write "  #{STYLES[:muted]}#{i + 1}.  #{opt[:label]}#{Ansi::RESET}#{Ansi::CRLF}"
        end
        write "#{Ansi::CRLF}  #{STYLES[:prompt]}#{step[:prompt]}#{Ansi::RESET} "

        input = readline&.strip
        return :halt if input.nil?

        index = input.to_i - 1
        unless (0...step[:options].length).include?(index)
          write "#{Ansi::CRLF}  #{STYLES[:error]}Enter a number between 1 and #{step[:options].length}.#{Ansi::RESET}#{Ansi::CRLF}"
          next
        end

        result = execute(step[:options][index][:steps])
        return :halt if result == :halt
        return nil   if result == :exit_menu

        break unless step[:loop]
      end
      nil
    end

    def run_call(step)
      result = step[:block].call(@ctx, self)
      result == :halt ? :halt : nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    rescue => e
      warn "BBS call error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      write "#{Ansi::CRLF}  #{Ansi::BRIGHT_RED}Error: #{e.message}#{Ansi::RESET}#{Ansi::CRLF * 2}"
      nil
    end

    def run_line(step)
      color = style_color(step[:color])
      write "  #{color}#{'─' * 66}#{Ansi::RESET}#{Ansi::CRLF}"
    end

    def run_section(step)
      color = style_color(step[:color])
      title = step[:title]
      pad   = [70 - title.length - 6, 2].max
      write "#{Ansi::CRLF}  #{color}┌─ #{Ansi::WHITE}#{title} #{color}#{'─' * pad}┐#{Ansi::RESET}#{Ansi::CRLF * 2}"
    end

    def run_text(step)
      color   = style_color(step[:style])
      content = step[:block] ? step[:block].call(@ctx) : step[:text]
      write "  #{color}#{content}#{Ansi::RESET}#{Ansi::CRLF}" if content
    end

    def run_rows(step)
      items = step[:block].call(@ctx)
      items = Array(items)
      if items.empty?
        write "  #{STYLES[:muted]}#{step[:empty]}#{Ansi::RESET}#{Ansi::CRLF}"
      else
        items.each { |row| write "  #{row}#{Ansi::CRLF}" }
      end
      nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    rescue => e
      warn "BBS rows error: #{e.class}: #{e.message}"
      write "#{Ansi::CRLF}  #{STYLES[:error]}Error loading content.#{Ansi::RESET}#{Ansi::CRLF}"
      nil
    end

    def run_table(step)
      pairs = step[:block].call(@ctx)
      pairs.each do |label, value|
        write "  #{STYLES[:muted]}#{label.to_s.ljust(16)}#{STYLES[:prompt]}#{value}#{Ansi::RESET}#{Ansi::CRLF}"
      end
      nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    rescue => e
      warn "BBS table error: #{e.class}: #{e.message}"
      write "#{Ansi::CRLF}  #{STYLES[:error]}Error loading content.#{Ansi::RESET}#{Ansi::CRLF}"
      nil
    end

    def run_wait_enter(step)
      write "#{Ansi::CRLF}  #{STYLES[:muted]}#{step[:prompt]}#{Ansi::RESET}"
      return :halt if readline.nil?
      nil
    end

    def run_fetch(step)
      write "#{Ansi::CRLF}  #{STYLES[:muted]}#{step[:loading]}#{Ansi::RESET}#{Ansi::CRLF}"
      result = step[:block].call(@ctx)
      write ERASE_LINE_ABOVE
      @ctx[step[:name]] = result
      nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    rescue => e
      warn "BBS fetch error: #{e.class}: #{e.message}"
      write "#{Ansi::CRLF}  #{STYLES[:error]}Error loading content.#{Ansi::RESET}#{Ansi::CRLF}"
      nil
    end

    def run_pick(step)
      items = Array(@ctx[step[:from]]).first(25)

      if items.empty?
        write "#{Ansi::CRLF}  #{STYLES[:error]}#{step[:empty]}#{Ansi::RESET}#{Ansi::CRLF}"
        write "#{Ansi::CRLF}  #{STYLES[:muted]}Press ENTER to continue...#{Ansi::RESET}"
        return :halt if readline.nil?
        return nil
      end

      write Ansi::CRLF
      items.each_with_index do |item, i|
        write "  #{step[:item].call(item, i + 1)}#{Ansi::CRLF}"
        if step[:hint]
          hint = step[:hint].call(item, i + 1).to_s.strip
          write "     #{STYLES[:muted]}#{hint}#{Ansi::RESET}#{Ansi::CRLF}" unless hint.empty?
        end
      end

      write "#{Ansi::CRLF}  #{STYLES[:muted]}#{step[:prompt]}#{Ansi::RESET} "
      input = readline&.strip
      return :halt if input.nil?
      return nil   if input.empty?

      picked = input.match?(NUMBER) && input.to_i.between?(1, items.size) ? items[input.to_i - 1] : nil
      unless picked
        write "#{Ansi::CRLF}  #{STYLES[:error]}Invalid selection.#{Ansi::RESET}#{Ansi::CRLF}"
        return nil
      end

      @ctx[:picked] = picked
      write Ansi::CRLF
      execute(step[:sub_steps])
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    end

    def run_body(step)
      text   = strip_md(step[:block].call(@ctx).to_s)
      width  = step[:width]
      prefix = ' ' * step[:indent]
      words  = text.split
      lines  = []
      line   = +''
      words.each do |word|
        if line.empty?
          line << word
        elsif line.length + 1 + word.length <= width
          line << ' ' << word
        else
          lines << line.dup
          line = +word
        end
      end
      lines << line unless line.empty?
      write Ansi::CRLF
      lines.each { |l| write "#{prefix}#{l}#{Ansi::CRLF}" }
      write Ansi::CRLF
      nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    rescue => e
      warn "BBS body error: #{e.class}: #{e.message}"
      nil
    end

    def run_output(step)
      content = step[:block].call(@ctx).to_s
      write content unless content.empty?
      nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    rescue => e
      warn "BBS output error: #{e.class}: #{e.message}"
      write "#{Ansi::CRLF}  #{STYLES[:error]}Error rendering content.#{Ansi::RESET}#{Ansi::CRLF}"
      nil
    end

    def run_tui(step)
      TUIRunner.new(@session, @session_id, step[:definition], context: @ctx).run
      nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    end

    def run_app(step)
      step[:definition].run(session: @session, session_id: @session_id, context: @ctx)
      nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    end

    def run_os(step)
      FakeOS::Runner.new(@session, step[:definition], context: @ctx).run
      nil
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      :halt
    end

    # ── helpers ────────────────────────────────────────────────────────────────

    def strip_md(text)
      text.gsub(Patterns::MARKDOWN_LINK, '\1')
          .gsub(Patterns::MARKDOWN_MARK, '')
          .gsub(Patterns::LINE_BREAKS, ' ')
          .strip
    end

    def style_color(value)
      value.is_a?(Symbol) ? STYLES.fetch(value, STYLES[:muted]) : value.to_s
    end

    def apply_transform(value, transform)
      case transform
      when :upcase   then value.upcase
      when :downcase then value.downcase
      when Proc      then transform.call(value)
      else value
      end
    end

    def valid?(value, validator)
      case validator
      when :email     then value.match?(EMAIL)
      when :non_empty then !value.empty?
      when Proc, Method then validator.call(value) ? true : false
      else true
      end
    end

    def validation_message(validator)
      case validator
      when :email then "That doesn't look like a valid email address. Farewell."
      else "Invalid input. Farewell."
      end
    end
  end
end
