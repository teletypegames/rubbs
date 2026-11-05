# frozen_string_literal: true

module UI
  module Modern
    # The guestbook's two windows: the entries, and the form that signs it.
    module GuestbookWindows
      extend Rubbs::Modern::Part

      window :entries, :master_detail do
        title 'Guestbook'
        height(-6)
        items { guestbook.all }
        label { |entry| "#{entry.day} #{entry.name}" }
        detail { |entry| [bright(entry.name), dim(entry.written.strftime('%Y-%m-%d %H:%M')), '', entry.text] }
        empty 'Nobody has signed yet. Be the first: F3.'
        action('Sign') { show(:sign) }
      end

      window :register, :form do
        title 'New account'
        field :name, label: 'Name', max_length: 20
        field :password, label: 'Password', password: true, max_length: 200
        field :again, label: 'Again', password: true, max_length: 200
        errors Wording::REGISTER
        on_submit do |values|
          found = directory.register(values[:name], values[:password], values[:again])
          next found unless found.is_a?(Rubbs::Common::Auth::Identity)

          session.identity = found
          message "Welcome, #{found.name}.", title: 'New account'
        end
      end

      window :sign, :form do
        title 'Sign the guestbook'
        field :name, label: 'Name', max_length: 30, value: -> { identity.name.to_s }
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
