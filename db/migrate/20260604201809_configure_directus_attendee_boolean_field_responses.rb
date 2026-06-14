# frozen_string_literal: true

class ConfigureDirectusAttendeeBooleanFieldResponses < ActiveRecord::Migration[8.1]
  def up
    conn = ActiveRecord::Base.connection

    # Collection metadata
    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, icon, display_template)
      VALUES ('attendee_boolean_field_responses', true, 'check_box', '{{event_boolean_field_id.translations.label}}')
      ON CONFLICT (collection) DO UPDATE
        SET hidden           = true,
            icon             = EXCLUDED.icon,
            display_template = EXCLUDED.display_template
    SQL

    # Field interfaces — DELETE first to avoid duplicates (no unique constraint)
    fields = [
      { field: 'id',                    hidden: true,  interface: nil,                    readonly: false, options: nil,                                         special: nil },
      { field: 'attendee_id',           hidden: true,  interface: nil,                    readonly: false, options: nil,                                         special: nil },
      { field: 'created_at',            hidden: true,  interface: nil,                    readonly: false, options: nil,                                         special: nil },
      { field: 'updated_at',            hidden: true,  interface: nil,                    readonly: false, options: nil,                                         special: nil },
      { field: 'event_boolean_field_id', hidden: false, interface: 'select-dropdown-m2o', readonly: true,  options: '{"template":"{{translations.label}}"}',     special: nil },
      { field: 'value', hidden: false, interface: 'boolean', readonly: true, options: nil, special: nil }
    ]

    fields.each do |f|
      execute("DELETE FROM directus_fields WHERE collection = 'attendee_boolean_field_responses' AND field = #{conn.quote(f[:field])}")
      iface = f[:interface] ? conn.quote(f[:interface]) : 'NULL'
      opts  = f[:options]   ? conn.quote(f[:options])   : 'NULL'
      spec  = f[:special]   ? conn.quote(f[:special])   : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, interface, hidden, readonly, options, special, width)
        VALUES ('attendee_boolean_field_responses', #{conn.quote(f[:field])}, #{iface}, #{f[:hidden]}, #{f[:readonly]}, #{opts}::json, #{spec}, 'full')
      SQL
    end

    # O2M virtual field on attendees — DELETE first, then insert (not readonly so rows are clickable)
    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'boolean_field_responses'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('attendees', 'boolean_field_responses', 'list-o2m', false, false, 'o2m',
              '{"enableCreate":false,"enableSelect":false,"enableDelete":false}'::json, 'full')
    SQL

    # Relation: attendee_boolean_field_responses.attendee_id → attendees
    execute(<<~SQL)
      INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
      VALUES ('attendee_boolean_field_responses', 'attendee_id', 'attendees', 'boolean_field_responses', NULL, 'delete')
      ON CONFLICT DO NOTHING
    SQL

    # Update if already existed with wrong one_field
    execute(<<~SQL)
      UPDATE directus_relations
      SET one_field = 'boolean_field_responses', one_deselect_action = 'delete'
      WHERE many_collection = 'attendee_boolean_field_responses' AND many_field = 'attendee_id'
    SQL

    # Relation: attendee_boolean_field_responses.event_boolean_field_id → event_boolean_fields
    execute(<<~SQL)
      INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
      VALUES ('attendee_boolean_field_responses', 'event_boolean_field_id', 'event_boolean_fields', NULL, NULL, 'nullify')
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'boolean_field_responses'")
    execute("DELETE FROM directus_fields WHERE collection = 'attendee_boolean_field_responses'")
    execute("DELETE FROM directus_relations WHERE many_collection = 'attendee_boolean_field_responses' AND many_field IN ('attendee_id','event_boolean_field_id')")
    execute("UPDATE directus_collections SET hidden = false, icon = NULL, display_template = NULL WHERE collection = 'attendee_boolean_field_responses'")
  end
end
