# frozen_string_literal: true

# The guestbook's rules: a name and a text, not too long. It answers with a
# Symbol the faces put in words (UI::Wording::SIGN).
class GuestbookService
  def initialize(entries, max_length:)
    @entries    = entries
    @max_length = max_length
  end

  def all = @entries.all

  # :ok, :no_name, :empty or :too_long.
  def sign(name, text)
    name = BBS::Text.line(name.to_s)
    text = BBS::Text.line(text.to_s)
    return :no_name if name.empty?
    return :empty if text.empty?
    return :too_long if text.length > @max_length

    @entries.add(name, text)
    :ok
  end
end
