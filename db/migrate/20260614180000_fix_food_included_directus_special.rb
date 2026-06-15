# frozen_string_literal: true

class FixFoodIncludedDirectusSpecial < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      UPDATE directus_fields
      SET special = 'cast-boolean'
      WHERE collection = 'tickets' AND field = 'food_included'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET special = NULL
      WHERE collection = 'tickets' AND field = 'food_included'
    SQL
  end
end
