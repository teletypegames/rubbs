# frozen_string_literal: true

require 'sequel'
require_relative 'database'

module BBS
  # The model of one table of a board's database: a Sequel::Model whose
  # table is named in the class and whose database is bound when the board
  # starts (BBS::Domain's +database+), so a model file needs no connection
  # to load.
  #
  #   class EntryModel < BBS::Model
  #     table :entries
  #
  #     def self.newest = reverse(:id)
  #     def day = Time.at(written_at).strftime('%Y-%m-%d')
  #   end
  #
  #   EntryModel.all
  #   EntryModel.where(name: 'ada').newest.limit(10).all
  #   EntryModel.create(name: 'ada', text: 'hello', written_at: Time.now.to_i)
  #   EntryModel[3]&.update(text: 'better')
  #   EntryModel.db.fetch('SELECT … FROM fts WHERE fts MATCH ?', words)   # plain SQL where it is needed
  #
  # Everything of Sequel::Model is there: datasets (+where+, +order+,
  # +group_and_count+, +exclude+ …), associations (<tt>many_to_one :game,
  # class: 'GameModel'</tt>), hooks and validations. A board's database may
  # be more than one: <tt>table :rfcs, database: :index</tt>.
  #
  # Until a board binds its databases the models stand on a mock one.
  class Model < Sequel::Model(Sequel.mock(host: 'sqlite'))
    class << self
      # Names the model's +table+ in the database +database+ (+:main+ by
      # default, the board's first).
      def table(name, database: :main)
        @table = [name.to_sym, database.to_sym]
        Model.tables << self unless Model.tables.include?(self)
      end

      # The table named with ::table and its database, or +nil+.
      def table_name_and_database = @table

      # The models that named a table, in the order they did.
      def tables = Model.instance_variable_get(:@tables) || Model.instance_variable_set(:@tables, [])

      # Binds every model to its table in +databases+ (a Hash of
      # Sequel::Database by name); a model whose database is not among them
      # is left as it was.
      def bind(databases)
        tables.each do |model|
          table, database = model.table_name_and_database
          model.dataset = databases[database][table] if databases.key?(database)
        end
      end
    end
  end
end
