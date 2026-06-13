# frozen_string_literal: true

class CreateEventTemplateDocs < ActiveRecord::Migration[8.1]
  def change
    create_table :event_template_docs do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.uuid    :directus_files_id, null: false
      t.string  :label,             null: false
      t.integer :sort,              null: false, default: 0

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_foreign_key :event_template_docs, :directus_files,
                    column: :directus_files_id,
                    name: 'event_template_docs_directus_files_id_foreign'
    add_index :event_template_docs, %i[event_id sort]
  end
end
