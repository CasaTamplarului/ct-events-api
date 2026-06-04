# frozen_string_literal: true

class FixDirectusBooleanFieldsCollectionVisibility < ActiveRecord::Migration[8.1]
  # Completes the Directus CMS configuration for boolean choice fields:
  # - Hides sub-collections (managed through events form, not standalone)
  # - Adds the boolean_fields O2M repeater to the events collection
  # Safe to run on instances where the previous migration already added fields/relations.

  def up
    conn = ActiveRecord::Base.connection

    # Hide sub-collections and set icons
    [
      { collection: 'event_boolean_fields',             icon: 'toggle_on',   display_template: '{{translations.label}}' },
      { collection: 'event_boolean_field_translations', icon: 'translate',    display_template: nil },
      { collection: 'attendee_boolean_field_responses', icon: 'how_to_vote',  display_template: nil }
    ].each do |c|
      dt = c[:display_template] ? conn.quote(c[:display_template]) : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_collections (collection, hidden, icon, display_template)
        VALUES (#{conn.quote(c[:collection])}, true, #{conn.quote(c[:icon])}, #{dt})
        ON CONFLICT (collection) DO UPDATE
          SET hidden = true,
              icon   = EXCLUDED.icon,
              display_template = EXCLUDED.display_template
      SQL
    end

    # Add boolean_fields O2M repeater on the events collection (like template_docs)
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, options, special, width)
      VALUES ('events', 'boolean_fields', 'list-o2m', false, '{"enableCreate":true,"enableSelect":false}'::json, 'o2m', 'full')
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute("DELETE FROM directus_fields WHERE collection = 'events' AND field = 'boolean_fields'")
    execute("UPDATE directus_collections SET hidden = false, icon = NULL, display_template = NULL WHERE collection IN ('event_boolean_fields','event_boolean_field_translations','attendee_boolean_field_responses')")
  end
end
