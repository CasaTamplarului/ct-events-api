# frozen_string_literal: true

class CreateEventTemplateDocTranslationsAndRemoveLabel < ActiveRecord::Migration[8.1]
  def change
    create_table :event_template_doc_translations do |t|
      t.references :event_template_doc, null: false, foreign_key: { on_delete: :cascade }
      t.string :languages_code, null: false
      t.string :label, null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :event_template_doc_translations, %i[event_template_doc_id languages_code], unique: true,
                                                                                          name: 'index_event_template_doc_translations_unique'
    add_foreign_key :event_template_doc_translations, :languages, column: :languages_code,
                                                                  primary_key: :code

    remove_column :event_template_docs, :label, :string
  end
end
