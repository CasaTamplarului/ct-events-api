# frozen_string_literal: true

class FixTicketsDisplayTemplate < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      UPDATE directus_collections
      SET display_template = '{{translations.name}}'
      WHERE collection = 'tickets'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_collections
      SET display_template = '{{id}} — ${{price}}'
      WHERE collection = 'tickets'
    SQL
  end
end
