# frozen_string_literal: true

class RegisterDirectusBooleanFieldsMetadata < ActiveRecord::Migration[8.1]
  # Registers event_boolean_fields and event_boolean_field_translations in Directus's
  # internal metadata tables so the collections appear correctly in the CMS UI.
  # Uses INSERT ... ON CONFLICT DO NOTHING so it is safe to run multiple times.

  def up
    fields = [
      { collection: 'event_boolean_fields', field: 'sort',        interface: 'input',                hidden: false, options: nil,                                                                                    special: nil },
      { collection: 'event_boolean_fields', field: 'required',    interface: 'boolean',              hidden: false, options: nil,                                                                                    special: nil },
      { collection: 'event_boolean_fields', field: 'display_as',  interface: 'select-dropdown',     hidden: false, options: '{"choices":[{"text":"Toggle","value":"toggle"},{"text":"Checkbox","value":"checkbox"}]}', special: nil },
      { collection: 'event_boolean_fields', field: 'translations', interface: 'translations',        hidden: false, options: '{"defaultLanguage":"ro-RO","defaultOpenSplitView":true,"languageField":"name"}',        special: 'translations' },
      { collection: 'event_boolean_field_translations', field: 'label',          interface: 'input',               hidden: false, options: nil,                      special: nil },
      { collection: 'event_boolean_field_translations', field: 'true_label',     interface: 'input',               hidden: false, options: nil,                      special: nil },
      { collection: 'event_boolean_field_translations', field: 'false_label',    interface: 'input',               hidden: false, options: nil,                      special: nil },
      { collection: 'event_boolean_field_translations', field: 'languages_code', interface: 'select-dropdown-m2o', hidden: false, options: '{"template":"{{name}}"}', special: nil }
    ]

    conn = ActiveRecord::Base.connection
    fields.each do |f|
      opts  = f[:options] ? conn.quote(f[:options]) : 'NULL'
      spec  = f[:special] ? conn.quote(f[:special]) : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, interface, hidden, options, special, width)
        VALUES (#{conn.quote(f[:collection])}, #{conn.quote(f[:field])}, #{conn.quote(f[:interface])}, #{f[:hidden]}, #{opts}::json, #{spec}, 'full')
        ON CONFLICT DO NOTHING
      SQL
    end

    relations = [
      { many_collection: 'event_boolean_fields',             many_field: 'event_id',                one_collection: 'events',                one_field: 'boolean_fields', junction_field: nil,                       one_deselect_action: 'delete'  },
      { many_collection: 'event_boolean_field_translations', many_field: 'event_boolean_field_id',  one_collection: 'event_boolean_fields',  one_field: 'translations',   junction_field: 'languages_code',           one_deselect_action: 'nullify' },
      { many_collection: 'event_boolean_field_translations', many_field: 'languages_code',          one_collection: 'languages',             one_field: nil,              junction_field: 'event_boolean_field_id',   one_deselect_action: 'nullify' }
    ]

    relations.each do |r|
      junc = r[:junction_field] ? conn.quote(r[:junction_field]) : 'NULL'
      one_f = r[:one_field] ? conn.quote(r[:one_field]) : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field, one_deselect_action)
        VALUES (#{conn.quote(r[:many_collection])}, #{conn.quote(r[:many_field])}, #{conn.quote(r[:one_collection])}, #{one_f}, #{junc}, #{conn.quote(r[:one_deselect_action])})
        ON CONFLICT DO NOTHING
      SQL
    end
  end

  def down
    execute("DELETE FROM directus_fields WHERE collection IN ('event_boolean_fields','event_boolean_field_translations') AND field IN ('sort','required','display_as','translations','label','true_label','false_label','languages_code')")
    execute("DELETE FROM directus_relations WHERE many_collection IN ('event_boolean_fields','event_boolean_field_translations')")
  end
end
