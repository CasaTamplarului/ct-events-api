# frozen_string_literal: true

class AddHiddenToTickets < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :hidden, :boolean, default: false, null: false

    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'hidden'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('tickets', 'hidden', 'boolean', false, false, 'cast-boolean',
              '{"label":"Hidden (admin only)"}'::json, 'half')
    SQL
  end

  def down
    remove_column :tickets, :hidden
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'hidden'")
  end
end
