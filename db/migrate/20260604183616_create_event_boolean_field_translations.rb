# frozen_string_literal: true

class CreateEventBooleanFieldTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :event_boolean_field_translations do |t|
      t.references :event_boolean_field, null: false, foreign_key: { on_delete: :cascade }
      t.string :languages_code, null: false
      t.string :label,          null: false
      t.string :true_label,     null: false
      t.string :false_label,    null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :event_boolean_field_translations,
              %i[event_boolean_field_id languages_code],
              unique: true,
              name: 'idx_event_boolean_field_translations_unique'

    add_foreign_key :event_boolean_field_translations, :languages,
                    column: :languages_code,
                    primary_key: :code,
                    name: 'event_boolean_field_translations_languages_code_fk'
  end
end
