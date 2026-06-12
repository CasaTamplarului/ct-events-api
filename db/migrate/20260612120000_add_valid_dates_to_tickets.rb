# frozen_string_literal: true

class AddValidDatesToTickets < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :valid_from, :date
    add_column :tickets, :valid_to,   :date

    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field IN ('valid_from', 'valid_to')")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES
        ('tickets', 'valid_from', 'datetime', false, false, NULL, NULL, 'half'),
        ('tickets', 'valid_to',   'datetime', false, false, NULL, NULL, 'half')
    SQL
  end

  def down
    remove_column :tickets, :valid_from
    remove_column :tickets, :valid_to
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field IN ('valid_from', 'valid_to')")
  end
end
