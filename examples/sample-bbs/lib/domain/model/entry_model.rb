# frozen_string_literal: true

# One line in the guestbook: who wrote what, and when.
EntryModel = Data.define(:id, :name, :text, :written_at) do
  def self.from_row(row)
    new(id: row['id'], name: row['name'], text: row['text'], written_at: Time.at(row['written_at']))
  end

  def day = written_at.strftime('%Y-%m-%d')
end
