# frozen_string_literal: true

class RegisterDirectusBooleanFieldsMetadata < ActiveRecord::Migration[8.1]
  # Registers event_boolean_fields and event_boolean_field_translations in Directus's
  # internal metadata tables so the collections appear in the CMS UI as nested
  # relations on the events form (same pattern as event_template_docs).
  # Uses INSERT ... ON CONFLICT DO NOTHING so it is safe to run multiple times.

  def up
    conn = ActiveRecord::Base.connection

    # ── directus_collections — hide sub-tables, expose through events form ──
    collections = [
      { collection: 'event_boolean_fields',             hidden: true,  icon: 'toggle_on',   display_template: '{{translations.label}}' },
      { collection: 'event_boolean_field_translations', hidden: true,  icon: 'translate',    display_template: nil },
      { collection: 'attendee_boolean_field_responses', hidden: true,  icon: 'how_to_vote',  display_template: nil }
    ]
    collections.each do |c|
      dt = c[:display_template] ? conn.quote(c[:display_template]) : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_collections (collection, hidden, icon, display_template)
        VALUES (#{conn.quote(c[:collection])}, #{c[:hidden]}, #{conn.quote(c[:icon])}, #{dt})
        ON CONFLICT (collection) DO UPDATE
          SET hidden = EXCLUDED.hidden,
              icon   = EXCLUDED.icon,
              display_template = EXCLUDED.display_template
      SQL
    end

    # ── directus_fields — field interfaces ───────────────────────────────────
    fields = [
      # events: O2M repeater for boolean_fields (like template_docs)
      { collection: 'events',                         field: 'boolean_fields',  interface: 'list-o2m',           hidden: false, options: '{"enableCreate":true,"enableSelect":false}', special: 'o2m' },
      # event_boolean_fields
      { collection: 'event_boolean_fields',           field: 'sort',            interface: 'input',              hidden: false, options: nil,                                                                                     special: nil },
      { collection: 'event_boolean_fields',           field: 'required',        interface: 'boolean',            hidden: false, options: nil,                                                                                     special: nil },
      { collection: 'event_boolean_fields',           field: 'display_as',      interface: 'select-dropdown',    hidden: false, options: '{"choices":[{"text":"Toggle","value":"toggle"},{"text":"Checkbox","value":"checkbox"}]}', special: nil },
      { collection: 'event_boolean_fields',           field: 'translations',    interface: 'translations',       hidden: false, options: '{"defaultLanguage":"ro-RO","defaultOpenSplitView":true,"languageField":"name"}',         special: 'translations' },
      # event_boolean_field_translations
      { collection: 'event_boolean_field_translations', field: 'label',          interface: 'input',               hidden: false, options: nil,                       special: nil },
      { collection: 'event_boolean_field_translations', field: 'true_label',     interface: 'input',               hidden: false, options: nil,                       special: nil },
      { collection: 'event_boolean_field_translations', field: 'false_label',    interface: 'input',               hidden: false, options: nil,                       special: nil },
      { collection: 'event_boolean_field_translations', field: 'languages_code', interface: 'select-dropdown-m2o', hidden: false, options: '{"template":"{{name}}"}',  special: nil }
    ]

    fields.each do |f|
      opts = f[:options] ? conn.quote(f[:options]) : 'NULL'
      spec = f[:special]  ? conn.quote(f[:special])  : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, interface, hidden, options, special, width)
        VALUES (#{conn.quote(f[:collection])}, #{conn.quote(f[:field])}, #{conn.quote(f[:interface])}, #{f[:hidden]}, #{opts}::json, #{spec}, 'full')
        ON CONFLICT DO NOTHING
      SQL
    end

    # ── directus_relations ───────────────────────────────────────────────────
    relations = [
      # event_boolean_fields.event_id → events  (M2O; surfaces as boolean_fields repeater on events)
      { many_collection: 'event_boolean_fields',             many_field: 'event_id',               one_collection: 'events',               one_field: 'boolean_fields', junction_field: nil,                     one_deselect_action: 'delete'  },
      # event_boolean_field_translations.event_boolean_field_id → event_boolean_fields  (translations)
      { many_collection: 'event_boolean_field_translations', many_field: 'event_boolean_field_id', one_collection: 'event_boolean_fields', one_field: 'translations',   junction_field: 'languages_code',         one_deselect_action: 'nullify' },
      # event_boolean_field_translations.languages_code → languages
      { many_collection: 'event_boolean_field_translations', many_field: 'languages_code',         one_collection: 'languages',            one_field: nil,              junction_field: 'event_boolean_field_id', one_deselect_action: 'nullify' }
    ]

    relations.each do |r|
      junc  = r[:junction_field] ? conn.quote(r[:junction_field]) : 'NULL'
      one_f = r[:one_field]      ? conn.quote(r[:one_field])      : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
        VALUES (#{conn.quote(r[:many_collection])}, #{conn.quote(r[:many_field])}, #{conn.quote(r[:one_collection])}, #{one_f}, #{junc}, #{conn.quote(r[:one_deselect_action])})
        ON CONFLICT DO NOTHING
      SQL
    end
  end

  def down
    execute("DELETE FROM directus_fields WHERE (collection = 'events' AND field = 'boolean_fields') OR collection IN ('event_boolean_fields','event_boolean_field_translations')")
    execute("DELETE FROM directus_relations WHERE many_collection IN ('event_boolean_fields','event_boolean_field_translations')")
    execute("UPDATE directus_collections SET hidden = false, icon = NULL, display_template = NULL WHERE collection IN ('event_boolean_fields','event_boolean_field_translations','attendee_boolean_field_responses')")
  end
end
