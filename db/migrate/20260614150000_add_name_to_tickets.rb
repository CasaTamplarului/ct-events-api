# frozen_string_literal: true

class AddNameToTickets < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :name, :string

    # Backfill from ro-RO translation
    execute(<<~SQL)
      UPDATE tickets t
      SET name = tt.name
      FROM tickets_translations tt
      WHERE tt.tickets_id = t.id AND tt.languages_code = 'ro-RO'
    SQL

    # Keep in sync whenever translations are saved
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION sync_ticket_name_from_translation()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.languages_code = 'ro-RO' THEN
          UPDATE tickets SET name = NEW.name WHERE id = NEW.tickets_id;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute(<<~SQL)
      CREATE TRIGGER tickets_translations_sync_name
      AFTER INSERT OR UPDATE ON tickets_translations
      FOR EACH ROW EXECUTE FUNCTION sync_ticket_name_from_translation();
    SQL

    # Update display template to use the direct column
    execute(<<~SQL)
      UPDATE directus_collections SET display_template = '{{name}}' WHERE collection = 'tickets'
    SQL

    # Register field in Directus (hidden in edit forms — it auto-syncs from translations)
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, width)
      VALUES ('tickets', 'name', 'input', true, true, 'full')
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute("DROP TRIGGER IF EXISTS tickets_translations_sync_name ON tickets_translations")
    execute("DROP FUNCTION IF EXISTS sync_ticket_name_from_translation()")
    execute("UPDATE directus_collections SET display_template = '{{id}} — ${{price}}' WHERE collection = 'tickets'")
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'name'")
    remove_column :tickets, :name
  end
end
