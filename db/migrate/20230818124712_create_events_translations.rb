class CreateEventsTranslations < ActiveRecord::Migration[7.0]
  def change
    create_table :events_translations do |t|
      t.integer :events_id
      t.string :languages_code
      t.string :name, null: false
      t.string :description, null: false

      t.timestamps
    end

    add_foreign_key :events_translations, :languages, column: :languages_code, primary_key: :code, on_delete: :nullify
    add_foreign_key :events_translations, :events, column: :events_id, primary_key: :id, on_delete: :nullify
  end
end
