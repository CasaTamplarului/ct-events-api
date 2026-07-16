# frozen_string_literal: true

class AddRegistrationClosesAtToEvents < ActiveRecord::Migration[7.1]
  def up
    add_column :events, :registration_closes_at, :datetime

    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, width)
      VALUES ('events', 'registration_closes_at', 'datetime', false, false, 'half')
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    remove_column :events, :registration_closes_at

    execute(<<~SQL)
      DELETE FROM directus_fields WHERE collection = 'events' AND field = 'registration_closes_at'
    SQL
  end
end
