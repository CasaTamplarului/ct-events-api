# frozen_string_literal: true

class RegisterDirectusDescriptionSectionsMetadata < ActiveRecord::Migration[8.1]
  COLLECTIONS = %w[event_description_sections event_description_section_translations].freeze

  def up
    conn = ActiveRecord::Base.connection

    # ── directus_collections ─────────────────────────────────────────────────
    [
      { collection: 'event_description_sections',             hidden: true, icon: 'view_list',  display_template: '{{translations.label}}', sort_field: 'sort' },
      { collection: 'event_description_section_translations', hidden: true, icon: 'translate',  display_template: nil,                      sort_field: nil }
    ].each do |c|
      dt = c[:display_template] ? conn.quote(c[:display_template]) : 'NULL'
      sf = c[:sort_field]       ? conn.quote(c[:sort_field])       : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_collections (collection, hidden, icon, display_template, sort_field)
        VALUES (#{conn.quote(c[:collection])}, true, #{conn.quote(c[:icon])}, #{dt}, #{sf})
        ON CONFLICT (collection) DO UPDATE
          SET hidden           = true,
              icon             = EXCLUDED.icon,
              display_template = EXCLUDED.display_template,
              sort_field       = EXCLUDED.sort_field
      SQL
    end

    # ── directus_fields ───────────────────────────────────────────────────────
    # Delete before insert to prevent duplicates (directus_fields has no unique constraint)
    execute(<<~SQL)
      DELETE FROM directus_fields
      WHERE (collection = 'events' AND field = 'description_sections')
         OR collection IN ('event_description_sections', 'event_description_section_translations')
    SQL

    [
      # O2M repeater on events
      { collection: 'events',                                  field: 'description_sections', interface: 'list-o2m',            hidden: false, options: '{"enableCreate":true,"enableSelect":false}',                                    special: 'o2m'          },
      # event_description_sections fields
      { collection: 'event_description_sections',             field: 'sort',                 interface: 'input',               hidden: false, options: nil,                                                                               special: nil            },
      { collection: 'event_description_sections',             field: 'translations',         interface: 'translations',        hidden: false, options: '{"defaultLanguage":"ro-RO","defaultOpenSplitView":true,"languageField":"name"}', special: 'translations' },
      # event_description_section_translations fields
      { collection: 'event_description_section_translations', field: 'languages_code',       interface: 'select-dropdown-m2o', hidden: false, options: '{"template":"{{name}}"}',                                                       special: nil            },
      { collection: 'event_description_section_translations', field: 'label',                interface: 'input',               hidden: false, options: nil,                                                                               special: nil            },
      { collection: 'event_description_section_translations', field: 'content',              interface: 'input-rich-text-html', hidden: false, options: nil,                                                                              special: nil            }
    ].each do |f|
      opts = f[:options] ? conn.quote(f[:options]) : 'NULL'
      spec = f[:special]  ? conn.quote(f[:special])  : 'NULL'
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, interface, hidden, options, special, width)
        VALUES (#{conn.quote(f[:collection])}, #{conn.quote(f[:field])}, #{conn.quote(f[:interface])}, #{f[:hidden]}, #{opts}::json, #{spec}, 'full')
      SQL
    end

    # ── directus_relations ────────────────────────────────────────────────────
    [
      # event_description_sections.event_id → events (surfaces as description_sections O2M on events)
      { many_collection: 'event_description_sections',             many_field: 'event_id',                       one_collection: 'events',                       one_field: 'description_sections', junction_field: nil,                               one_deselect_action: 'delete'  },
      # event_description_section_translations.event_description_section_id → event_description_sections (translations)
      { many_collection: 'event_description_section_translations', many_field: 'event_description_section_id',  one_collection: 'event_description_sections',   one_field: 'translations',          junction_field: 'languages_code',                  one_deselect_action: 'nullify' },
      # event_description_section_translations.languages_code → languages
      { many_collection: 'event_description_section_translations', many_field: 'languages_code',                one_collection: 'languages',                    one_field: nil,                     junction_field: 'event_description_section_id',    one_deselect_action: 'nullify' }
    ].each do |r|
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
    execute("DELETE FROM directus_fields WHERE (collection = 'events' AND field = 'description_sections') OR collection IN ('event_description_sections','event_description_section_translations')")
    execute("DELETE FROM directus_relations WHERE many_collection IN ('event_description_sections','event_description_section_translations')")
    execute("DELETE FROM directus_collections WHERE collection IN ('event_description_sections','event_description_section_translations')")
  end
end
