# frozen_string_literal: true

module UI
  module Modern
    # The guestbook's two windows: the entries, and the form that signs it.
    module GuestbookWindows
      extend BBS::Part

      window :entries, :master_detail do
        title 'Guestbook'
        height(-6)
        items { guestbook.all }
        label { |entry| "#{entry.day} #{entry.name}" }
        detail { |entry| [bright(entry.name), dim(entry.written_at.strftime('%Y-%m-%d %H:%M')), '', entry.text] }
        empty 'Nobody has signed yet. Be the first: F3.'
        action('Sign') { show(:sign) }
      end

      window :sign, :form do
        title 'Sign the guestbook'
        field :name, label: 'Name', max_length: 30
        field :text, label: 'Text', type: :textarea, max_length: 200
        errors Wording::SIGN.except(:ok)
        on_submit do |values|
          result = guestbook.sign(values[:name], values[:text])
          next result unless result == :ok

          reload_details
          message Wording::SIGN[:ok], title: 'Guestbook'
        end
      end
    end
  end
end
