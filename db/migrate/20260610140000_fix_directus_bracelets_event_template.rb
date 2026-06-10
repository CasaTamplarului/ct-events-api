# frozen_string_literal: true

class FixDirectusBraceletsEventTemplate < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      UPDATE directus_fields
      SET options = '{"template":"{{slug}}"}'::json
      WHERE collection = 'bracelets' AND field = 'event_id'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET options = '{"template":"{{name}}"}'::json
      WHERE collection = 'bracelets' AND field = 'event_id'
    SQL
  end
end
