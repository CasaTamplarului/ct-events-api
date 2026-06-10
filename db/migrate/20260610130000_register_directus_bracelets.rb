# frozen_string_literal: true

class RegisterDirectusBracelets < ActiveRecord::Migration[8.1]
  COLLECTION = 'bracelets'

  def up
    conn = ActiveRecord::Base.connection

    # ── Collection ────────────────────────────────────────────────────────────
    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, icon, display_template)
      VALUES ('bracelets', false, 'loyalty', '{{code}}')
      ON CONFLICT (collection) DO UPDATE
        SET hidden           = false,
            icon             = EXCLUDED.icon,
            display_template = EXCLUDED.display_template
    SQL

    # ── Fields ────────────────────────────────────────────────────────────────
    fields = [
      { field: 'id',          hidden: true,  interface: nil,                    readonly: false, special: nil,    options: nil },
      { field: 'code',        hidden: false, interface: 'input',                readonly: true,  special: nil,    options: nil },
      { field: 'event_id',    hidden: false, interface: 'select-dropdown-m2o',  readonly: false, special: nil,    options: '{"template":"{{name}}"}' },
      { field: 'attendee_id', hidden: false, interface: 'select-dropdown-m2o',  readonly: false, special: nil,    options: '{"template":"{{first_name}} {{last_name}}"}' },
      { field: 'created_at',  hidden: false, interface: 'datetime',             readonly: true,  special: 'date-created', options: nil },
      { field: 'updated_at',  hidden: true,  interface: nil,                    readonly: true,  special: 'date-updated', options: nil }
    ]

    fields.each do |f|
      execute("DELETE FROM directus_fields WHERE collection = 'bracelets' AND field = #{conn.quote(f[:field])}")
      iface = f[:interface] ? conn.quote(f[:interface]) : 'NULL'
      opts  = f[:options]   ? conn.quote(f[:options])   : 'NULL'
      spec  = f[:special]   ? conn.quote(f[:special])   : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, interface, hidden, readonly, options, special, width)
        VALUES ('bracelets', #{conn.quote(f[:field])}, #{iface}, #{f[:hidden]}, #{f[:readonly]}, #{opts}::json, #{spec}, 'half')
      SQL
    end

    # ── O2M virtual field on events ───────────────────────────────────────────
    execute("DELETE FROM directus_fields WHERE collection = 'events' AND field = 'bracelets'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('events', 'bracelets', 'list-o2m', false, true, 'o2m',
              '{"enableCreate":false,"enableSelect":false,"enableDelete":false}'::json, 'full')
    SQL

    # ── O2M virtual field on attendees ────────────────────────────────────────
    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'bracelet'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('attendees', 'bracelet', 'list-o2m', false, true, 'o2m',
              '{"enableCreate":false,"enableSelect":false,"enableDelete":false}'::json, 'full')
    SQL

    # ── Relations ─────────────────────────────────────────────────────────────

    # bracelets.event_id → events.bracelets
    execute("DELETE FROM directus_relations WHERE many_collection = 'bracelets' AND many_field = 'event_id'")
    execute(<<~SQL)
      INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
      VALUES ('bracelets', 'event_id', 'events', 'bracelets', NULL, 'nullify')
    SQL

    # bracelets.attendee_id → attendees.bracelet
    execute("DELETE FROM directus_relations WHERE many_collection = 'bracelets' AND many_field = 'attendee_id'")
    execute(<<~SQL)
      INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
      VALUES ('bracelets', 'attendee_id', 'attendees', 'bracelet', NULL, 'nullify')
    SQL
  end

  def down
    execute("DELETE FROM directus_fields WHERE collection = 'bracelets'")
    execute("DELETE FROM directus_fields WHERE collection = 'events' AND field = 'bracelets'")
    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'bracelet'")
    execute("DELETE FROM directus_relations WHERE many_collection = 'bracelets'")
    execute("UPDATE directus_collections SET hidden = true WHERE collection = 'bracelets'")
  end
end
