# frozen_string_literal: true

module BBS
  class FlowRunner
    STYLES = {
      success: "\e[1;32m",
      muted:   "\e[0;37m",
      error:   "\e[1;31m",
      info:    "\e[0;33m",
      prompt:  "\e[1;37m",
      confirm: "\e[1;36m",
    }.freeze

    def initialize(session, session_id, flow)
      @session    = session
      @session_id = session_id
      @flow       = flow
      @ctx        = {}
    end

    def run
      execute(@flow.steps)
    end

    private

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
      end
    end

    # ── step handlers ──────────────────────────────────────────────────────────

    def run_screen(step)
      vars = step[:vars].transform_values { |v| v.is_a?(Symbol) ? @ctx[v] : v }
      write Renderer.render(step[:name].to_s, @ctx.merge(vars))
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
      write "\r\n  #{color}#{step[:text]}\e[0m\r\n\r\n"
    end

    def run_set(step)
      @ctx[step[:name]] = step[:value]
      nil
    end

    def run_ask(step)
      write "  #{STYLES[:prompt]}#{step[:prompt]}\e[0m: "
      value = readline&.strip
      return :halt if value.nil?

      value = apply_transform(value, step[:transform])

      if step[:validate] && !valid?(value, step[:validate])
        write "\r\n  #{STYLES[:error]}#{validation_message(step[:validate])}\e[0m\r\n\r\n"
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
      write "\r\n  #{STYLES[:info]}#{step[:message]}\e[0m\r\n"
      sleep step[:seconds]
      nil
    end

    def run_gate(step)
      return nil if step[:check].call(@ctx)
      write "  #{STYLES[:error]}#{step[:denied]}\e[0m\r\n\r\n"
      :halt
    end

    def run_confirm_halt(step)
      write "\r\n  #{STYLES[:confirm]}#{step[:message]}\e[0m [yes/no]: "
      answer = readline&.strip&.downcase
      return :halt if answer.nil?
      return nil   if %w[yes y].include?(answer)
      write "\r\n  #{STYLES[:muted]}#{step[:denied]}\e[0m\r\n\r\n" if step[:denied]
      :halt
    end

    def run_confirm_block(step)
      write "\r\n  #{STYLES[:prompt]}#{step[:message]}\e[0m [yes/no]: "
      answer = readline&.strip&.downcase
      return :halt if answer.nil?

      if %w[yes y].include?(answer)
        execute(step[:sub_steps])
      else
        write "\r\n  #{STYLES[:muted]}#{step[:denied]}\e[0m\r\n\r\n" if step[:denied]
        nil
      end
    end

    def run_menu(step)
      loop do
        write "\r\n"
        step[:options].each_with_index do |opt, i|
          write "  #{STYLES[:muted]}#{i + 1}.  #{opt[:label]}\e[0m\r\n"
        end
        write "\r\n  #{STYLES[:prompt]}#{step[:prompt]}\e[0m "

        input = readline&.strip
        return :halt if input.nil?

        index = input.to_i - 1
        unless (0...step[:options].length).include?(index)
          write "\r\n  #{STYLES[:error]}Enter a number between 1 and #{step[:options].length}.\e[0m\r\n"
          next
        end

        result = execute(step[:options][index][:steps])
        return :halt if result == :halt
        return nil   if result == :exit_menu

        break unless step[:loop]
      end
      nil
    end

    # ── helpers ────────────────────────────────────────────────────────────────

    def apply_transform(value, transform)
      case transform
      when :upcase   then value.upcase
      when :downcase then value.downcase
      else value
      end
    end

    def valid?(value, validator)
      case validator
      when :email     then value.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      when :non_empty then !value.empty?
      else true
      end
    end

    def validation_message(validator)
      case validator
      when :email then "That doesn't look like a valid email address. Farewell."
      else "Invalid input. Farewell."
      end
    end

    def write(data) = @session.write(data)
    def readline    = @session.readline
  end
end
