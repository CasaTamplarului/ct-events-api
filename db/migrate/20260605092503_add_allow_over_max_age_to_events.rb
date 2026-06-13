# frozen_string_literal: true

class AddAllowOverMaxAgeToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :allow_over_max_age, :boolean, default: false, null: false

    ActiveRecord::Base.connection
    execute("DELETE FROM directus_fields WHERE collection = 'events' AND field = 'allow_over_max_age'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('events', 'allow_over_max_age', 'boolean', false, false, 'cast-boolean',
              '{"label":"Allow over max age (shows e.g. 26+)"}'::json, 'half')
    SQL
  end

  def down
    remove_column :events, :allow_over_max_age
    execute("DELETE FROM directus_fields WHERE collection = 'events' AND field = 'allow_over_max_age'")
  end
end
