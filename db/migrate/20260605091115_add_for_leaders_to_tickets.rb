# frozen_string_literal: true

class AddForLeadersToTickets < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :for_leaders, :boolean, default: false, null: false

    ActiveRecord::Base.connection
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'for_leaders'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('tickets', 'for_leaders', 'boolean', false, false, 'cast-boolean',
              '{"label":"Leaders only"}'::json, 'half')
    SQL
  end

  def down
    remove_column :tickets, :for_leaders
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'for_leaders'")
  end
end
