# frozen_string_literal: true

class CreateTicketsAllowedUsers < ActiveRecord::Migration[8.1]
  def up
    create_table :tickets_allowed_users do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
    end

    add_index :tickets_allowed_users, %i[ticket_id user_id], unique: true

    # Register junction collection (hidden from nav)
    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, singleton, icon)
      VALUES ('tickets_allowed_users', true, false, 'import_export')
      ON CONFLICT DO NOTHING
    SQL

    # Register junction fields (hidden in UI — they are FK columns)
    execute("DELETE FROM directus_fields WHERE collection = 'tickets_allowed_users'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, hidden, readonly)
      VALUES
        ('tickets_allowed_users', 'id', true, true),
        ('tickets_allowed_users', 'ticket_id', true, true),
        ('tickets_allowed_users', 'user_id', true, true)
    SQL

    # Register M2M alias field on tickets (the user-picker that appears in the Directus form)
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'allowed_users'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('tickets', 'allowed_users', 'list-m2m', false, false, 'm2m',
              '{"template":"{{first_name}} {{last_name}} ({{email}})"}'::json, 'full')
    SQL

    # Register M2M relations — one_deselect_action must be 'delete' (not 'nullify')
    # because both FK columns are NOT NULL; nullifying would fail with a constraint error
    execute("DELETE FROM directus_relations WHERE many_collection = 'tickets_allowed_users'")
    execute(<<~SQL)
      INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
      VALUES
        ('tickets_allowed_users', 'ticket_id', 'tickets', 'allowed_users', 'user_id', 'delete'),
        ('tickets_allowed_users', 'user_id', 'users', null, 'ticket_id', 'delete')
    SQL
  end

  def down
    execute("DELETE FROM directus_relations WHERE many_collection = 'tickets_allowed_users'")
    execute("DELETE FROM directus_fields WHERE collection = 'tickets_allowed_users'")
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'allowed_users'")
    execute("DELETE FROM directus_collections WHERE collection = 'tickets_allowed_users'")
    drop_table :tickets_allowed_users
  end
end
