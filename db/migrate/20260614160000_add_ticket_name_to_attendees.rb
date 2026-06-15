# frozen_string_literal: true

class AddTicketNameToAttendees < ActiveRecord::Migration[8.1]
  def up
    add_column :attendees, :ticket_name, :string

    # Backfill from tickets.name (already synced from ro-RO translations)
    execute(<<~SQL)
      UPDATE attendees a
      SET ticket_name = t.name
      FROM tickets t
      WHERE t.id = a.ticket_id
    SQL

    # Keep in sync when a new attendee is created
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION sync_attendee_ticket_name()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.ticket_id IS NOT NULL THEN
          SELECT name INTO NEW.ticket_name FROM tickets WHERE id = NEW.ticket_id;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute(<<~SQL)
      CREATE TRIGGER attendees_sync_ticket_name
      BEFORE INSERT ON attendees
      FOR EACH ROW EXECUTE FUNCTION sync_attendee_ticket_name();
    SQL

    # Register in Directus
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, width)
      VALUES ('attendees', 'ticket_name', 'input', false, true, 'half')
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute("DROP TRIGGER IF EXISTS attendees_sync_ticket_name ON attendees")
    execute("DROP FUNCTION IF EXISTS sync_attendee_ticket_name()")
    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'ticket_name'")
    remove_column :attendees, :ticket_name
  end
end
