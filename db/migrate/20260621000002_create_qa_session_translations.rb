class CreateQaSessionTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :qa_session_translations do |t|
      t.references :qa_session, null: false, foreign_key: { on_delete: :cascade }
      t.string :languages_code, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :qa_session_translations, %i[qa_session_id languages_code],
              unique: true, name: 'idx_qa_session_translations_unique'
    add_foreign_key :qa_session_translations, :languages,
                    column: :languages_code, primary_key: :code
  end
end
