# frozen_string_literal: true

require_relative 'container'
require_relative 'focus_manager'

module BBS
  # A Window is a top-level Container with its own border, title, and focus
  # manager. The Application stacks windows; the top window is the modal /
  # active one and receives input first.
  class Window < Container
    attr_accessor :title, :modal, :shadow, :on_close, :close_key

    def initialize(title: nil, modal: false, shadow: true, on_close: nil,
                   close_key: :escape, **kw)
      super(**kw)
      @title     = title
      @modal     = modal
      @shadow    = shadow
      @on_close  = on_close
      @close_key = close_key
      @focus_mgr = nil
    end

    def focus_manager
      @focus_mgr ||= FocusManager.new(self)
    end

    def reset_focus
      @focus_mgr = FocusManager.new(self)
    end

    def render(frame)
      if @shadow
        frame.shadow(x: bounds.x, y: bounds.y, width: bounds.width,
                     height: bounds.height, sgr: style(:window_shadow))
      end
      show_close = @on_close != false && bounds.width >= 6
      frame.box(
        x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height,
        sgr: style(:window_border), fill_sgr: style(:window_bg),
        style: :double, title: @title,
        title_sgr: focused ? style(:window_title_focused) : style(:window_title),
        title_indent: show_close ? 4 : 0
      )
      # Close gadget — Turbo Vision style "[■]"
      if show_close
        frame.move(bounds.x + 2, bounds.y)
        frame.write('[■]', sgr: style(:window_title))
      end
      @children.each { |c| c.render(frame) if c.visible }
    end

    def hit_test(x, y)
      # close gadget area
      if @on_close != false && y == bounds.y &&
         x >= bounds.x + 2 && x <= bounds.x + 4
        return self
      end
      super
    end

    def handle_event(event)
      if event.mouse? && event.mouse.kind == :press && event.mouse.button == :left
        if event.y == bounds.y && event.x >= bounds.x + 2 && event.x <= bounds.x + 4
          return close
        end
        if event.mouse.button == :left
          hit = hit_test(event.x, event.y)
          focus_manager.focus(hit) if hit&.focusable?
        end
      end

      result = focus_manager.handle_focus_key(event) ? :handled : nil
      result ||= focus_manager.dispatch(event)
      return result if result

      if event.key? && event.key == @close_key
        return close
      end
      nil
    end

    def close
      @on_close&.call(self)
      :close_window
    end
  end
end
