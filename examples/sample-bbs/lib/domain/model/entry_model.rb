# frozen_string_literal: true

# One line in the guestbook: who wrote what, and when.
class EntryModel < Rubbs::Common::Storage::Model
  table :entries

  def self.newest = reverse(:id).all

  def self.sign(name, text) = create(name: name, text: text, written_at: Time.now.to_i)

  def written = Time.at(written_at)

  def day = written.strftime('%Y-%m-%d')
end
