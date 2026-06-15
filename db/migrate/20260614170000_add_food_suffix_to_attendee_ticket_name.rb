# frozen_string_literal: true

class AddFoodSuffixToAttendeeTicketName < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION sync_attendee_ticket_name()
      RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.ticket_id IS NOT NULL THEN
          SELECT name || CASE WHEN food_included THEN ' (cu mâncare)' ELSE ' (fără mâncare)' END
          INTO NEW.ticket_name FROM tickets WHERE id = NEW.ticket_id;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute(<<~SQL)
      UPDATE attendees a
      SET ticket_name = t.name || CASE WHEN t.food_included THEN ' (cu mâncare)' ELSE ' (fără mâncare)' END
      FROM tickets t
      WHERE t.id = a.ticket_id
    SQL
  end

  def down
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
      UPDATE attendees a
      SET ticket_name = t.name
      FROM tickets t
      WHERE t.id = a.ticket_id
    SQL
  end
end
