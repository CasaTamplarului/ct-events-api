# frozen_string_literal: true

class CreateAttendeesWithTicketNameView < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      CREATE OR REPLACE VIEW attendees_ticket_summary AS
      SELECT
        a.id,
        a.event_id,
        a.ticket_id,
        a.payment_status,
        a.checked_in,
        tt.name AS ticket_name
      FROM attendees a
      LEFT JOIN tickets_translations tt
        ON tt.tickets_id = a.ticket_id AND tt.languages_code = 'ro-RO'
    SQL

    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, singleton, icon, note)
      VALUES ('attendees_ticket_summary', false, false, 'bar_chart', 'Read-only view for Insights charts')
      ON CONFLICT DO NOTHING
    SQL

    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special)
      VALUES
        ('attendees_ticket_summary', 'id',             null,             true,  true, null),
        ('attendees_ticket_summary', 'event_id',       'select-dropdown-m2o', false, true, null),
        ('attendees_ticket_summary', 'ticket_id',      'select-dropdown-m2o', false, true, null),
        ('attendees_ticket_summary', 'ticket_name',    'input',          false, true, null),
        ('attendees_ticket_summary', 'payment_status', 'select-dropdown', false, true, null),
        ('attendees_ticket_summary', 'checked_in',     'boolean',         false, true, null)
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute("DELETE FROM directus_fields WHERE collection = 'attendees_ticket_summary'")
    execute("DELETE FROM directus_collections WHERE collection = 'attendees_ticket_summary'")
    execute("DROP VIEW IF EXISTS attendees_ticket_summary")
  end
end
