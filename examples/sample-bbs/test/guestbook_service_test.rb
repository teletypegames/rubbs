# frozen_string_literal: true

require 'test_helper'

class GuestbookServiceTest < Minitest::Test
  include TmpGuestbook

  def test_a_signature_is_kept_newest_first
    assert_equal :ok, @guestbook.sign('ada', 'hello')
    assert_equal :ok, @guestbook.sign('bob', 'hi there')
    assert_equal %w[bob ada], @guestbook.all.map(&:name)
  end

  def test_what_the_guestbook_refuses
    assert_equal :no_name, @guestbook.sign(' ', 'hello')
    assert_equal :empty, @guestbook.sign('ada', '')
    assert_equal :too_long, @guestbook.sign('ada', 'x' * 21)
    assert_empty @guestbook.all
  end
end
