# frozen_string_literal: true

module Rubbs
  module Common
    module Screens
      class Selector
        # The items one under the other in one or more columns, a page of
        # +height+ rows at a time: the layout of a Rubbs::Common::Screens::Selector without
        # +across+.
        class Columns
          # The rows of items a page shows, and the columns side by side.
          attr_reader :height, :columns

          # Lays out +count+ items in +columns+ columns of +height+ rows
          # (default: all the items, shared out among the columns); with
          # +fill+ a page keeps +height+ rows even when the items take fewer.
          def initialize(count, height:, columns:, fill:)
            @count   = count
            @columns = columns.clamp(1, count)
            natural  = (count + @columns - 1) / @columns
            @height  = (height || natural).clamp(1, fill && height ? height : count)
          end

          # The rows of items on the screen: #height.
          def item_rows = @height

          # The items on a page.
          def per_page = @height * @columns

          # The pages the items take.
          def pages = (@count + per_page - 1) / per_page

          # The page item +index+ is on, from 0.
          def page_of(index) = index / per_page

          # The screen row of item +index+, from 1.
          def line_of(index) = (index % per_page % @height) + 1

          # The screen column item +index+ starts at, from 1, in a menu
          # +width+ wide.
          def column_of(index, width) = 1 + (width / @columns * (index % per_page / @height))

          # The cells of screen row +number+ of +selector+'s page: the cell of
          # each column side by side, the last column taking what the others
          # leave.
          def segments(number, selector)
            first = (selector.page * per_page) + number - 1
            cell  = selector.width / @columns
            (0...@columns).flat_map do |c|
              width = c == @columns - 1 ? selector.width - (cell * c) : cell
              selector.cell(first + (c * @height), width)
            end
          end

          # Moves +selector+ sideways by +dir+: to the nearest selectable item
          # in the column beside, or to the page beside when there is none.
          def side(selector, dir)
            return selector.turn(dir) if @columns == 1

            target = selector.index + (dir * @height)
            return selector.turn(dir) unless same_page?(selector, target)

            column = column_from(selector, target)
            selector.jump(column.min_by { |i| [(i - target).abs, i < target ? 1 : 0] }) unless column.empty?
          end

          private

          def same_page?(selector, target)
            target.between?(0, @count - 1) && page_of(target) == selector.page
          end

          def column_from(selector, target)
            top = target - (target % per_page % @height)
            (top...[top + @height, @count].min).select { |i| selector.selectable?(i) }
          end
        end

        # All the items side by side on one row: the layout of a Rubbs::Common::Screens::Selector
        # with +across+. The items that do not fit are left off.
        class Row
          # Lays out +count+ items on one row.
          def initialize(count)
            @count = count
          end

          # One row of items.
          def item_rows = 1

          # Every item is on the one page.
          def per_page = @count

          # One page.
          def pages = 1

          # Always the first page.
          def page_of(_index) = 0

          # Always the first row.
          def line_of(_index) = 1

          # Always the first column: the cursor waits at the row's start.
          def column_of(_index, _width) = 1

          # The words of the items on the row, the lit one a bar.
          def segments(_number, selector) = selector.across_cells

          # Moves +selector+ to the item before or after.
          def side(selector, dir) = selector.move(dir)
        end
      end
    end
  end
end
