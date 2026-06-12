# frozen_string_literal: true

class CreateEventDescriptionSectionTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :event_description_section_translations do |t|
      t.references :event_description_section, null: false, foreign_key: { on_delete: :cascade }
      t.string :languages_code, null: false
      t.string :label
      t.text :content

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :event_description_section_translations,
              %i[event_description_section_id languages_code],
              unique: true,
              name: 'idx_event_desc_section_translations_unique'

    add_foreign_key :event_description_section_translations, :languages,
                    column: :languages_code,
                    primary_key: :code,
                    name: 'event_desc_section_translations_languages_code_fk'
  end
end
